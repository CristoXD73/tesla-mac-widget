import CoreImage.CIFilterBuiltins
import SwiftUI

@main
struct TeslaWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(model)
        } label: {
            Image(systemName: model.snapshot?.isCharging == true ? "bolt.car.fill" : "car.side.fill")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var sigterm: DispatchSourceSignal?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // OAuth comes back as teslawidget://callback?code=…
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Logout, `kill` and login-item shutdowns send SIGTERM; take the proxy down with us.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        sigterm = source

        Task { @MainActor in
            let model = AppModel.shared
            model.reloadCredentials()
            model.start()
            if !model.signedIn { SetupWindow.open() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.proxy.stop() }
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        Task { @MainActor in
            if url.host == "open-tesla" {
                // Widget tapped outside the buttons: open the Tesla app via iPhone Mirroring.
                await TeslaAppLauncher.open()
            } else {
                SetupWindow.open()
                await AppModel.shared.handleCallback(url)
            }
        }
    }
}

/// Plain AppKit window: SwiftUI's openWindow isn't reachable at launch in a menu-bar-only app.
@MainActor
enum SetupWindow {
    private static var window: NSWindow?

    static func open() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SetupView().environmentObject(AppModel.shared)))
            w.title = "Tesla Widget"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.moveToActiveSpace]
            window = w
        }
        guard let window else { return }
        // Menu bar apps have no Dock icon to click, so always bring the window to the screen in use.
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            window.setFrameTopLeftPoint(NSPoint(x: f.midX - window.frame.width / 2, y: f.maxY - 80))
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

// MARK: - Menu

struct MenuContent: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let s = model.snapshot {
            Text("\(s.name): \(s.batteryLevel.map { "\($0)%" } ?? "--") · \(s.rangeText ?? "") · \(s.statusLine)")
            if let d = s.dataFetchedAt { Text("Updated \(d.formatted(.relative(presentation: .named)))") }
        } else {
            Text(model.signedIn ? "No data yet" : "Not set up")
        }
        if let m = model.message { Text(m) }
        Divider()
        Button("Refresh Now") { Task { await model.refreshNow() } }
            .disabled(!model.signedIn || model.busy != nil)
        Button("Reload Car Image & Icons") { Task { await model.refreshCarImage() } }
            .disabled(model.busy != nil)
        Button("Setup & Status…") { SetupWindow.open() }
        Divider()
        Text(String(format: "API usage this month: $%.2f of $%.0f credit", model.usage.estimatedCost, Usage.monthlyCredit))
        Toggle("Open at Login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
        Divider()
        Button("Quit Tesla Widget") { NSApp.terminate(nil) }
    }
}

// MARK: - Setup window

struct SetupView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tesla Widget setup").font(.title2.bold())

            Step(n: 1, title: "Developer credentials", done: model.credentials != nil) {
                Text("Paste your Client ID, Client Secret and website into credentials.env, then click Reload.")
                HStack {
                    Button("Open credentials.env") {
                        // .env has no default app on macOS, so always use TextEdit.
                        NSWorkspace.shared.open([Credentials.file],
                                                withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                                configuration: NSWorkspace.OpenConfiguration())
                    }
                    Button("Reload") { model.reloadCredentials() }
                }
            }

            Step(n: 2, title: "Register with Tesla", done: model.registered) {
                Text("Links your app to the public key on \(model.credentials?.website.isEmpty == false ? model.credentials!.website : "your website (TESLA_WEBSITE in credentials.env)").")
                Button("Register") { Task { await model.registerWithTesla() } }
                    .disabled(model.credentials == nil || model.busy != nil)
            }

            Step(n: 3, title: "Sign in to Tesla", done: model.signedIn) {
                if model.signedIn, let name = model.config?.vehicleName ?? model.snapshot?.name {
                    Text("Connected to \(name.trimmingCharacters(in: .whitespaces)).")
                    Button("Sign Out") { model.signOut() }
                } else {
                    Text("Opens Tesla's sign-in page in your browser, then comes back here.")
                    Button("Sign In") { model.signIn() }
                        .disabled(!model.registered || model.busy != nil)
                }
            }

            Step(n: 4, title: "Pair the key with your car (for buttons)", done: model.keyPaired == true) {
                HStack(alignment: .top, spacing: 14) {
                    if let site = model.credentials?.website, !site.isEmpty, let qr = QRCode.image(Shared.pairingURL(site).absoluteString) {
                        Image(nsImage: qr).interpolation(.none).resizable().frame(width: 110, height: 110)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Scan with your iPhone camera, approve in the Tesla app, then tap your key card on the car's console when it asks.")
                        if let site = model.credentials?.website, !site.isEmpty {
                            Text(Shared.pairingURL(site).absoluteString).font(.caption).textSelection(.enabled).foregroundStyle(.secondary)
                        }
                        Button("Check Pairing") { Task { await model.checkKeyPaired() } }
                            .disabled(!model.signedIn)
                    }
                }
            }

            Step(n: 5, title: "Add the widget", done: false, showCheck: false) {
                Text("Right-click the desktop → Edit Widgets → search \"Tesla Widget\" → drag the size you want onto the desktop. You can remove the old iPhone Tesla widget.")
            }

            Divider()
            HStack {
                if let busy = model.busy { ProgressView().controlSize(.small); Text(busy) }
                if let m = model.message { Text(m).foregroundStyle(.red).textSelection(.enabled) }
                Spacer()
                Text(String(format: "Usage: $%.2f / $%.0f", model.usage.estimatedCost, Usage.monthlyCredit))
                    .foregroundStyle(.secondary)
                if !model.proxy.isRunning {
                    Label("Proxy stopped", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .help(model.proxy.lastError ?? "")
                }
            }
            .font(.caption)
        }
        .padding(22)
        .frame(width: 520)
        .task { if model.signedIn && model.keyPaired == nil { await model.checkKeyPaired() } }
    }
}

private struct Step<Content: View>: View {
    var n: Int
    var title: String
    var done: Bool
    var showCheck = true
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(n).circle")
                .font(.title2)
                .foregroundStyle(done && showCheck ? .green : .secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                content.font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

enum QRCode {
    static func image(_ string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
