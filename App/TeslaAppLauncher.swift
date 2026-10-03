import AppKit
import ApplicationServices

/// Opens the iPhone Tesla app through iPhone Mirroring, like tapping Tesla's own iPhone widget on a Mac.
/// Apple doesn't expose a way to launch a specific iPhone app, so this opens iPhone Mirroring and uses
/// its iPhone Spotlight shortcut (⌘3) to open Tesla. Typing needs Accessibility permission;
/// without it we just bring up iPhone Mirroring.
@MainActor
enum TeslaAppLauncher {
    private static let mirroringID = "com.apple.ScreenContinuity"
    private static let mirroringURL = URL(fileURLWithPath: "/System/Applications/iPhone Mirroring.app")
    private static var running = false

    static func open() async {
        guard !running else { return }
        running = true
        defer { running = false }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try? await NSWorkspace.shared.openApplication(at: mirroringURL, configuration: config)

        guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) else { return }

        // Wait for Mirroring to be frontmost and give it a moment to connect to the phone.
        for _ in 0..<40 where NSWorkspace.shared.frontmostApplication?.bundleIdentifier != mirroringID {
            try? await Task.sleep(for: .milliseconds(150))
        }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == mirroringID else { return }
        try? await Task.sleep(for: .milliseconds(1800))

        key(20, flags: .maskCommand)              // ⌘3 → iPhone Spotlight
        try? await Task.sleep(for: .milliseconds(700))
        type("Tesla")
        try? await Task.sleep(for: .milliseconds(900))
        key(36)                                   // Return opens the top hit
    }

    private static func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    private static func type(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        for ch in text.utf16 {
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
                var c = ch
                e?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
                e?.post(tap: .cghidEventTap)
            }
            usleep(25_000)
        }
    }
}
