import Foundation

/// Widget button commands. The widget applies the expected result immediately and hands the
/// command to the app (which keeps a warm token and proxy session) to actually send.
enum CarCommand: String, CaseIterable {
    case lock, unlock, climateOn = "climate_on", climateOff = "climate_off", frunk, trunk, homelink

    static let notificationPrefix = Shared.appGroup + ".command."
    var notificationName: Notification.Name { Notification.Name(Self.notificationPrefix + rawValue) }

    /// What the widget should show right away.
    func applyOptimistically(to s: inout VehicleSnapshot) {
        switch self {
        case .lock: s.locked = true
        case .unlock: s.locked = false
        case .climateOn: s.climateOn = true
        case .climateOff: s.climateOn = false
        case .frunk, .trunk, .homelink: break
        }
        s.pendingCommand = rawValue
        s.pendingSince = Date()
        s.lastError = nil
    }

    func send(with client: FleetClient, snapshot s: VehicleSnapshot) async throws {
        switch self {
        case .lock: try await client.command(vin: s.vin, "door_lock")
        case .unlock: try await client.command(vin: s.vin, "door_unlock")
        case .climateOn: try await client.command(vin: s.vin, "auto_conditioning_start")
        case .climateOff: try await client.command(vin: s.vin, "auto_conditioning_stop")
        case .frunk: try await client.command(vin: s.vin, "actuate_trunk", body: ["which_trunk": "front"])
        case .trunk: try await client.command(vin: s.vin, "actuate_trunk", body: ["which_trunk": "rear"])
        case .homelink:
            guard let lat = s.latitude, let lon = s.longitude else {
                throw FleetError(status: 0, message: "Car location unknown")
            }
            try await client.command(vin: s.vin, "trigger_homelink", body: ["lat": lat, "lon": lon])
        }
    }
}
