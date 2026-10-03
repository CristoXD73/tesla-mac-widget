import AppKit
import CoreLocation
import MapKit
import ServiceManagement
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var snapshot = Shared.load(VehicleSnapshot.self, VehicleSnapshot.file)
    @Published var config = Shared.load(Config.self, Config.file)
    @Published var tokens = Shared.load(Tokens.self, Tokens.file)
    @Published var usage = Usage.current
    @Published var credentials: Credentials? = Credentials.load()
    @Published var keyPaired: Bool?
    @Published var busy: String?
    @Published var message: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    let proxy = ProxyRunner()
    private var timer: Timer?
    private var oauthState: String?
    private var screensAsleep = false
    private var lastStateCheck = Date.distantPast
    private var lastDataFetch = Date.distantPast

    var signedIn: Bool { tokens != nil && config?.vin != nil }
    var registered: Bool { config?.registeredRegions.contains(config?.fleetBase.host ?? "") == true }

    // MARK: Lifecycle

    func start() {
        proxy.start()
        lastDataFetch = snapshot?.dataFetchedAt ?? .distantPast
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in await AppModel.shared.tick() }
        }
        DistributedNotificationCenter.default().addObserver(forName: Shared.refreshNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                AppModel.shared.reloadFromDisk()
                try? await Task.sleep(for: .seconds(4))
                await AppModel.shared.refresh(reason: "after command")
            }
        }
        for command in CarCommand.allCases {
            DistributedNotificationCenter.default().addObserver(forName: command.notificationName, object: nil, queue: .main) { _ in
                Task { @MainActor in await AppModel.shared.run(command) }
            }
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AppModel.shared.screensAsleep = true }
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                AppModel.shared.screensAsleep = false
                await AppModel.shared.tick()
            }
        }
        CarRender.syncIconOverrides()
        Task {
            await CarRender.updateIfNeeded()
            await tick()
        }
    }

    func reloadFromDisk() {
        snapshot = Shared.load(VehicleSnapshot.self, VehicleSnapshot.file)
        usage = Usage.current
    }

    // MARK: Polling

    /// Runs every minute. Polls just often enough to stay under Tesla's monthly credit,
    /// and never wakes the car on its own.
    func tick() async {
        usage = Usage.current
        guard signedIn, !screensAsleep, busy == nil else { return }
        if usage.estimatedCost >= Usage.monthlyCredit * 0.95 { return } // manual refresh only
        let slow: Double = usage.estimatedCost >= Usage.monthlyCredit * 0.8 ? 2 : 1

        let s = snapshot
        let active = s?.state == "online" && (s?.isCharging == true || s?.isDriving == true || s?.climateOn == true)
        let now = Date()
        if active {
            if now.timeIntervalSince(lastDataFetch) >= 5 * 60 * slow { await refresh(reason: "active") }
        } else if now.timeIntervalSince(lastStateCheck) >= 15 * 60 * slow {
            await refresh(reason: "scheduled", idleDataInterval: 30 * 60 * slow)
        }
    }

    /// Checks whether the car is awake and, if so (and the data is stale enough), fetches its data.
    func refresh(reason: String, idleDataInterval: TimeInterval = 0) async {
        guard let config, let vin = config.vin, let token = await validAccessToken() else { return }
        let client = FleetClient(config: config, accessToken: token)
        var snap = snapshot ?? VehicleSnapshot(vin: vin, name: config.vehicleName ?? "Tesla", state: "unknown", stateCheckedAt: Date())
        do {
            let state = try await client.vehicleState(vin: vin)
            lastStateCheck = Date()
            let wasOnline = snap.state == "online"
            snap.state = state
            snap.stateCheckedAt = Date()
            if state == "online" && (!wasOnline || Date().timeIntervalSince(lastDataFetch) >= idleDataInterval) {
                do {
                    let data = try await client.vehicleData(vin: vin)
                    var fresh = VehicleSnapshot(vin: vin, data: data, previous: snap)
                    fresh.lastError = snap.lastError
                    fresh.lastErrorAt = snap.lastErrorAt
                    snap = fresh
                    lastDataFetch = Date()
                    await saveVehicleInfoOnce(client: client, vin: vin, data: data)
                } catch let e as FleetError where e.isAsleep {
                    snap.state = "asleep"
                }
            }
            message = nil
        } catch {
            message = error.localizedDescription
        }
        snapshot = snap
        Shared.save(snap, VehicleSnapshot.file)
        usage = Usage.current
        WidgetCenter.shared.reloadAllTimelines()
        await updateLocationArt()
        writeDebugSnapshot()
    }

    /// Saves the car's configuration and option codes to ~/.tesla-widget/vehicle-info.json
    /// (once), so the matching official car render can be picked.
    private func saveVehicleInfoOnce(client: FleetClient, vin: String, data: [String: Any]) async {
        let url = Credentials.directory.appendingPathComponent("vehicle-info.json")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        var info: [String: Any] = ["vehicle_config": data["vehicle_config"] ?? NSNull()]
        if let options = try? await client.request(config?.fleetBase ?? Shared.defaultFleetBase, "api/1/dx/vehicles/options?vin=\(vin)") {
            info["options"] = options["response"] ?? options
        }
        if let json = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: url, options: .atomic)
        }
        await CarRender.updateIfNeeded(force: true)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Menu action: re-fetch the official car image (or pick up overrides/car.png) and any icon overrides.
    func refreshCarImage() async {
        busy = "Updating car image…"
        defer { busy = nil }
        CarRender.syncIconOverrides()
        await CarRender.updateIfNeeded(force: true)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Copy of the widget's data outside the App Group (which is TCC-protected) for troubleshooting.
    private func writeDebugSnapshot() {
        guard var s = snapshot else { return }
        s.vin = String(s.vin.suffix(4))
        if let lat = s.latitude, let lon = s.longitude {
            // Coarse location only.
            s.latitude = (lat * 100).rounded() / 100
            s.longitude = (lon * 100).rounded() / 100
        }
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: Credentials.directory.appendingPathComponent("snapshot-debug.json"), options: .atomic)
    }

    // MARK: Commands

    private var commandInFlight = false

    /// Sends a widget button's command. Tries straight away (the car is usually awake when
    /// you're about to use it) and only wakes it and retries if that fails.
    func run(_ command: CarCommand) async {
        reloadFromDisk() // pick up the widget's optimistic state
        guard !commandInFlight, var snap = snapshot, let config, let token = await validAccessToken() else { return }
        commandInFlight = true
        defer { commandInFlight = false }
        let client = FleetClient(config: config, accessToken: token)
        do {
            do {
                try await command.send(with: client, snapshot: snap)
            } catch let e as FleetError where e.status != 0 && e.status != 200 { // 200 = the car refused, retrying won't help
                // Asleep/offline/unreachable: wake it once and retry.
                try await client.ensureAwake(vin: snap.vin)
                try await command.send(with: client, snapshot: snap)
            }
            snap.lastError = nil
        } catch {
            snap.lastError = error.localizedDescription
            snap.lastErrorAt = Date()
        }
        snap.pendingCommand = nil
        snap.pendingSince = nil
        snapshot = snap
        Shared.save(snap, VehicleSnapshot.file)
        WidgetCenter.shared.reloadAllTimelines()
        // Confirm what the car actually did (also undoes the optimistic state on failure).
        try? await Task.sleep(for: .seconds(2))
        await refresh(reason: "after command")
    }

    /// Manual refresh from the menu: always fetches data if the car is awake.
    func refreshNow() async {
        busy = "Refreshing…"
        defer { busy = nil }
        await refresh(reason: "manual")
    }

    // MARK: Map + address

    private var artCoordinate: CLLocationCoordinate2D?

    private func updateLocationArt() async {
        guard var snap = snapshot, let lat = snap.latitude, let lon = snap.longitude else { return }
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let haveMaps = FileManager.default.fileExists(atPath: Shared.file("map-dark.png").path)
        if let old = artCoordinate, abs(old.latitude - lat) < 0.0005, abs(old.longitude - lon) < 0.0005,
           haveMaps, snap.address != nil { return }
        artCoordinate = coord

        if snap.address == nil || !haveMaps {
            if let placemark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon)).first {
                // Street only, like the Tesla widget ("123 Main Street").
                snap.address = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
                    .nilIfEmpty ?? placemark.name ?? placemark.locality
            }
            snapshot = snap
            Shared.save(snap, VehicleSnapshot.file)
        }
        for (name, appearance) in [("map-light.png", NSAppearance.Name.aqua), ("map-dark.png", .darkAqua)] {
            let options = MKMapSnapshotter.Options()
            options.region = MKCoordinateRegion(center: coord, latitudinalMeters: 500, longitudinalMeters: 500)
            options.size = NSSize(width: 640, height: 300)
            options.appearance = NSAppearance(named: appearance)
            options.pointOfInterestFilter = .excludingAll
            guard let shot = try? await MKMapSnapshotter(options: options).start() else { continue }
            let image = shot.image
            let point = shot.point(for: coord)
            let out = NSImage(size: image.size, flipped: false) { rect in
                image.draw(in: rect)
                let r: CGFloat = 9
                let flipped = NSPoint(x: point.x, y: image.size.height - point.y)
                let dot = NSBezierPath(ovalIn: NSRect(x: flipped.x - r, y: flipped.y - r, width: r * 2, height: r * 2))
                NSColor.white.setFill(); dot.fill()
                let inner = NSBezierPath(ovalIn: NSRect(x: flipped.x - r + 3, y: flipped.y - r + 3, width: (r - 3) * 2, height: (r - 3) * 2))
                NSColor.systemRed.setFill(); inner.fill()
                return true
            }
            if let tiff = out.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: Shared.file(name), options: .atomic)
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Setup steps

    func reloadCredentials() {
        credentials = Credentials.load()
        if let c = credentials {
            var cfg = config ?? Config(clientID: c.clientID)
            cfg.clientID = c.clientID
            save(cfg)
        }
    }

    /// One-time registration of our domain/public key with Tesla for the account's region.
    func registerWithTesla() async {
        guard let creds = credentials else { return }
        guard !creds.website.isEmpty else {
            message = "Add TESLA_WEBSITE=yourname.github.io to credentials.env, then click Reload."
            return
        }
        busy = "Registering with Tesla…"
        defer { busy = nil }
        var cfg = config ?? Config(clientID: creds.clientID)
        do {
            let partner = try await TeslaAuth.partnerToken(creds, audience: cfg.fleetBase)
            let client = FleetClient(config: cfg, accessToken: partner)
            _ = try await client.request(cfg.fleetBase, "api/1/partner_accounts", method: "POST", body: ["domain": creds.website])
            if let host = cfg.fleetBase.host, !cfg.registeredRegions.contains(host) { cfg.registeredRegions.append(host) }
            save(cfg)
            message = nil
        } catch {
            message = "Registration failed: \(error.localizedDescription)"
        }
    }

    func signIn() {
        guard let creds = credentials else { return }
        let state = UUID().uuidString
        oauthState = state
        NSWorkspace.shared.open(TeslaAuth.authorizeURL(creds, state: state))
    }

    func handleCallback(_ url: URL) async {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        NSApp.activate(ignoringOtherApps: true)
        if let error = value("error") { message = "Sign-in failed: \(value("error_description") ?? error)"; return }
        guard let code = value("code"), let creds = credentials else { return }
        guard oauthState == nil || value("state") == oauthState else { message = "Sign-in failed: state mismatch, try again"; return }

        busy = "Signing in…"
        defer { busy = nil }
        do {
            var cfg = config ?? Config(clientID: creds.clientID)
            let t = try await TeslaAuth.exchange(code: code, creds: creds, audience: cfg.fleetBase)
            saveTokens(t)
            var client = FleetClient(config: cfg, accessToken: t.accessToken)

            // Accounts outside North America live on a different regional server.
            if let region = try? await client.request(cfg.fleetBase, "api/1/users/region"),
               let base = (region["response"] as? [String: Any])?["fleet_api_base_url"] as? String,
               let url = URL(string: base), url.host != cfg.fleetBase.host {
                cfg.fleetBase = url
                save(cfg)
                await registerWithTesla()
                cfg = config ?? cfg
                client = FleetClient(config: cfg, accessToken: t.accessToken)
            }

            guard let car = try await client.vehicles().first, let vin = car["vin"] as? String else {
                message = "No cars found on this Tesla account"
                return
            }
            cfg.vin = vin
            cfg.vehicleName = (car["display_name"] as? String)?.trimmingCharacters(in: .whitespaces)
            save(cfg)
            message = nil
            await checkKeyPaired()
            await refresh(reason: "signed in")
        } catch {
            message = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    func checkKeyPaired() async {
        guard let config, let vin = config.vin, let token = await validAccessToken() else { return }
        keyPaired = try? await FleetClient(config: config, accessToken: token).keyPaired(vin: vin)
    }

    func signOut() {
        try? FileManager.default.removeItem(at: Shared.file(Tokens.file))
        try? FileManager.default.removeItem(at: Shared.file(VehicleSnapshot.file))
        tokens = nil
        snapshot = nil
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            message = "Couldn't change login item: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Tokens

    /// Returns an access token, refreshing it when it has less than an hour left.
    func validAccessToken() async -> String? {
        guard let t = tokens, let config else { return nil }
        if t.expiresAt.timeIntervalSinceNow > 3600 { return t.accessToken }
        do {
            let fresh = try await TeslaAuth.refresh(t, clientID: config.clientID)
            saveTokens(fresh)
            return fresh.accessToken
        } catch {
            message = "Tesla sign-in expired. Sign in again. (\(error.localizedDescription))"
            return t.expiresAt > Date() ? t.accessToken : nil
        }
    }

    private func saveTokens(_ t: Tokens) {
        tokens = t
        Shared.save(t, Tokens.file)
    }

    private func save(_ c: Config) {
        config = c
        Shared.save(c, Config.file)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
