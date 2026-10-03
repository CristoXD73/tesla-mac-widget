import Foundation

/// Constants and on-disk state shared by the app and the widget through the App Group container.
enum Shared {
    /// "<TEAM_ID>.<bundle prefix>.teslawidget", filled in at build time (see project.yml).
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "TWAppGroup") as? String ?? "group.teslawidget"
    static let widgetKind = "TeslaWidget"

    // Tesla developer app registration. `domain` is your website, e.g. "yourname.github.io".
    static func redirectURI(_ domain: String) -> String { "https://\(domain)/tesla-callback/" }
    static let authorizeURL = URL(string: "https://auth.tesla.com/oauth2/v3/authorize")!
    static let tokenURL = URL(string: "https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token")!
    static let defaultFleetBase = URL(string: "https://fleet-api.prd.na.vn.cloud.tesla.com")!
    static let userScopes = "openid offline_access vehicle_device_data vehicle_location vehicle_cmds vehicle_charging_cmds"
    static let partnerScopes = "openid vehicle_device_data vehicle_location vehicle_cmds vehicle_charging_cmds"
    static func pairingURL(_ domain: String) -> URL { URL(string: "https://tesla.com/_ak/\(domain)")! }

    // Local signing proxy (tesla-http-proxy), started by the app
    static let proxyBase = URL(string: "https://127.0.0.1:4443")!

    /// Posted by the widget after a command so the app fetches fresh data.
    static let refreshNotification = Notification.Name(appGroup + ".refresh")

    static var container: URL {
        #if RENDER_TOOL
        return FileManager.default.temporaryDirectory.appendingPathComponent("tesla-widget-render")
        #else
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.temporaryDirectory
        #endif
    }

    static func file(_ name: String) -> URL { container.appendingPathComponent(name) }

    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: file(name)) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: file(name), options: .atomic)
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

// MARK: - Persisted models

struct Tokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    static let file = "tokens.json"
}

struct Config: Codable {
    var clientID: String
    var fleetBase: URL = Shared.defaultFleetBase
    var vin: String?
    var vehicleName: String?
    var registeredRegions: [String] = []
    static let file = "config.json"
}

struct VehicleSnapshot: Codable {
    var vin: String
    var name: String
    /// "online", "asleep" or "offline"
    var state: String
    var stateCheckedAt: Date
    var dataFetchedAt: Date?

    var batteryLevel: Int?
    var rangeMiles: Double?
    var chargeLimit: Int?
    /// "Charging", "Complete", "Disconnected", "Stopped", "NoPower", "Starting"
    var chargingState: String?
    var minutesToFull: Int?

    var locked: Bool?
    var sentry: Bool?
    var odometer: Double?
    var shiftState: String?

    var climateOn: Bool?
    var insideTempC: Double?
    var outsideTempC: Double?

    var latitude: Double?
    var longitude: Double?
    var address: String?

    var usesCelsius: Bool = false
    var usesKilometers: Bool = false

    /// Set by the widget when a button is tapped, cleared by the app once the car answered.
    var pendingCommand: String?
    var pendingSince: Date?

    /// Shown in the widget when the last button press failed.
    var lastError: String?
    var lastErrorAt: Date?

    static let file = "snapshot.json"

    var isCharging: Bool { chargingState == "Charging" || chargingState == "Starting" }
    var isDriving: Bool { shiftState == "D" || shiftState == "R" || shiftState == "N" }
}

/// Running count of billable Fleet API calls this calendar month.
struct Usage: Codable {
    var month: String = Usage.currentMonth
    var dataCalls = 0
    var commandCalls = 0
    var wakeCalls = 0

    static let file = "usage.json"
    static let monthlyCredit = 10.0

    /// Tesla pay-per-use prices: data $0.002, commands $0.001, wakes $0.02.
    var estimatedCost: Double {
        Double(dataCalls) * 0.002 + Double(commandCalls) * 0.001 + Double(wakeCalls) * 0.02
    }

    static var currentMonth: String {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        return "\(c.year!)-\(c.month!)"
    }

    enum Kind { case data, command, wake }

    static func record(_ kind: Kind) {
        var u = Shared.load(Usage.self, file) ?? Usage()
        if u.month != currentMonth { u = Usage() }
        switch kind {
        case .data: u.dataCalls += 1
        case .command: u.commandCalls += 1
        case .wake: u.wakeCalls += 1
        }
        Shared.save(u, file)
    }

    static var current: Usage {
        let u = Shared.load(Usage.self, file) ?? Usage()
        return u.month == currentMonth ? u : Usage()
    }
}

// MARK: - Formatting

extension VehicleSnapshot {
    func temperature(_ celsius: Double?) -> String? {
        guard let c = celsius else { return nil }
        return usesCelsius ? "\(Int(c.rounded()))°" : "\(Int((c * 9 / 5 + 32).rounded()))°"
    }

    var rangeText: String? {
        guard let mi = rangeMiles else { return nil }
        return usesKilometers ? "\(Int((mi * 1.609).rounded())) km" : "\(Int(mi.rounded())) mi"
    }

    var statusLine: String {
        switch state {
        case "asleep": return "Asleep"
        case "offline": return "Offline"
        default: break
        }
        if isDriving { return shiftState == "D" ? "Driving" : "In \(shiftState ?? "gear")" }
        if isCharging {
            if let m = minutesToFull, m > 0 {
                let h = m / 60, mm = m % 60
                return h > 0 ? "Charging · \(h)h \(mm)m left" : "Charging · \(mm)m left"
            }
            return "Charging"
        }
        if chargingState == "Complete" { return "Charge complete" }
        if chargingState == "Stopped" { return "Plugged in" }
        return "Parked"
    }
}
