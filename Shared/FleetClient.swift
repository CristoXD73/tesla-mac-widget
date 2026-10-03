import Foundation

struct FleetError: LocalizedError {
    var status: Int
    var message: String
    var errorDescription: String? { message }

    /// Tesla answers 408 when the car is asleep or unreachable.
    var isAsleep: Bool { status == 408 }
}

/// Thin wrapper over Tesla Fleet API. Reads go straight to Tesla; commands go through the
/// local tesla-http-proxy, which signs them with our virtual key.
final class FleetClient: NSObject, URLSessionDelegate {
    let config: Config
    let accessToken: String

    /// DER of the proxy's self-signed certificate; the app copies it into the App Group.
    private let pinnedProxyCert = try? Data(contentsOf: Shared.file("proxy-cert.der"))
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

    init(config: Config, accessToken: String) {
        self.config = config
        self.accessToken = accessToken
    }

    // MARK: Reads

    func vehicles() async throws -> [[String: Any]] {
        let json = try await request(config.fleetBase, "api/1/vehicles")
        return json["response"] as? [[String: Any]] ?? []
    }

    /// Cheap state check that never wakes the car.
    func vehicleState(vin: String) async throws -> String {
        Usage.record(.data)
        let json = try await request(config.fleetBase, "api/1/vehicles/\(vin)")
        return (json["response"] as? [String: Any])?["state"] as? String ?? "unknown"
    }

    func vehicleData(vin: String) async throws -> [String: Any] {
        Usage.record(.data)
        // Tesla only honours more than one endpoint when the ";" separators are percent-encoded.
        let endpoints = ["charge_state", "climate_state", "drive_state", "location_data", "vehicle_state", "gui_settings", "vehicle_config"]
            .joined(separator: "%3B")
        let json = try await request(config.fleetBase, "api/1/vehicles/\(vin)/vehicle_data?endpoints=\(endpoints)")
        return json["response"] as? [String: Any] ?? [:]
    }

    func keyPaired(vin: String) async throws -> Bool {
        let json = try await request(config.fleetBase, "api/1/vehicles/fleet_status", method: "POST", body: ["vins": [vin]])
        let paired = (json["response"] as? [String: Any])?["key_paired_vins"] as? [String] ?? []
        return paired.contains(vin)
    }

    // MARK: Writes

    func wake(vin: String) async throws {
        Usage.record(.wake)
        _ = try await request(config.fleetBase, "api/1/vehicles/\(vin)/wake_up", method: "POST")
    }

    /// Wakes the car if needed and waits for it to come online (up to ~30 s).
    func ensureAwake(vin: String) async throws {
        if try await vehicleState(vin: vin) == "online" { return }
        try await wake(vin: vin)
        for _ in 0..<10 {
            try await Task.sleep(for: .seconds(3))
            if try await vehicleState(vin: vin) == "online" { return }
        }
        throw FleetError(status: 408, message: "Car didn't wake up")
    }

    func command(vin: String, _ name: String, body: [String: Any]? = nil) async throws {
        Usage.record(.command)
        let json: [String: Any]
        do {
            json = try await request(Shared.proxyBase, "api/1/vehicles/\(vin)/command/\(name)", method: "POST", body: body ?? [:], timeout: 25)
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .networkConnectionLost {
            throw FleetError(status: 0, message: "Tesla Widget app isn't running")
        }
        let response = json["response"] as? [String: Any]
        if response?["result"] as? Bool == false {
            let reason = response?["reason"] as? String ?? "rejected"
            throw FleetError(status: 200, message: "Car said: \(reason)")
        }
    }

    // MARK: Plumbing

    func request(_ base: URL, _ path: String, method: String = "GET", body: [String: Any]? = nil, timeout: TimeInterval = 20) async throws -> [String: Any] {
        guard let url = URL(string: path, relativeTo: base) else { throw FleetError(status: 0, message: "Bad URL \(path)") }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            let message = [json["error_description"], json["error"]].compactMap { $0 as? String }.first { !$0.isEmpty } ?? "HTTP \(status)"
            throw FleetError(status: status, message: status == 408 ? "Car is asleep" : message)
        }
        return json
    }

    /// Trust the proxy's self-signed certificate on 127.0.0.1 only, and only that exact certificate.
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == Shared.proxyBase.host,
              let trust = challenge.protectionSpace.serverTrust,
              let pinned = pinnedProxyCert,
              let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first,
              SecCertificateCopyData(leaf) as Data == pinned
        else { return (.performDefaultHandling, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }
}

// MARK: - Parsing

extension VehicleSnapshot {
    /// Builds a snapshot from a vehicle_data response, keeping the address from `previous`
    /// when the car hasn't moved.
    init(vin: String, data: [String: Any], previous: VehicleSnapshot?) {
        let charge = data["charge_state"] as? [String: Any] ?? [:]
        let climate = data["climate_state"] as? [String: Any] ?? [:]
        let drive = data["drive_state"] as? [String: Any] ?? [:]
        let vehicle = data["vehicle_state"] as? [String: Any] ?? [:]
        let gui = data["gui_settings"] as? [String: Any] ?? [:]

        self.init(
            vin: vin,
            name: (vehicle["vehicle_name"] as? String ?? data["display_name"] as? String ?? previous?.name ?? "Tesla")
                .trimmingCharacters(in: .whitespaces),
            state: "online",
            stateCheckedAt: Date(),
            dataFetchedAt: Date()
        )
        batteryLevel = charge["battery_level"] as? Int
        rangeMiles = charge["battery_range"] as? Double
        chargeLimit = charge["charge_limit_soc"] as? Int
        chargingState = charge["charging_state"] as? String
        minutesToFull = charge["minutes_to_full_charge"] as? Int
        locked = vehicle["locked"] as? Bool
        sentry = vehicle["sentry_mode"] as? Bool
        odometer = vehicle["odometer"] as? Double
        shiftState = drive["shift_state"] as? String
        climateOn = climate["is_climate_on"] as? Bool
        insideTempC = climate["inside_temp"] as? Double
        outsideTempC = climate["outside_temp"] as? Double
        latitude = drive["latitude"] as? Double ?? previous?.latitude
        longitude = drive["longitude"] as? Double ?? previous?.longitude
        usesCelsius = (gui["gui_temperature_units"] as? String) == "C"
        usesKilometers = (gui["gui_distance_units"] as? String)?.hasPrefix("km") == true

        if let p = previous, let la = p.latitude, let lo = p.longitude, let nla = latitude, let nlo = longitude,
           abs(la - nla) < 0.0005, abs(lo - nlo) < 0.0005 {
            address = p.address
        }
    }
}
