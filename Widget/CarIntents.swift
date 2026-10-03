import AppIntents
import Foundation
import WidgetKit

/// One intent for every widget button; `command` picks the Tesla command.
/// It only updates the widget and notifies the app, so the tap feels instant;
/// the app sends the command and confirms the real state afterwards.
struct CarCommandIntent: AppIntent {
    static var title: LocalizedStringResource = "Send command to car"
    static var isDiscoverable = false

    @Parameter(title: "Command") var command: String

    init() {}
    init(_ command: String) { self.command = command }

    func perform() async throws -> some IntentResult {
        guard let cmd = CarCommand(rawValue: command),
              var snapshot = Shared.load(VehicleSnapshot.self, VehicleSnapshot.file)
        else { return .result() }
        cmd.applyOptimistically(to: &snapshot)
        Shared.save(snapshot, VehicleSnapshot.file)
        DistributedNotificationCenter.default().postNotificationName(cmd.notificationName, object: nil, deliverImmediately: true)
        return .result()
    }
}
