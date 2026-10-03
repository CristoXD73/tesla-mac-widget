import Foundation
import Security

/// Runs Tesla's tesla-http-proxy while the app is open. The proxy signs car commands with
/// the private key in ~/.tesla-widget, which newer Teslas require.
final class ProxyRunner {
    private var process: Process?
    private var stopping = false
    private(set) var lastError: String?

    private let dir = Credentials.directory
    private var binary: URL { dir.appendingPathComponent("bin/tesla-http-proxy") }

    var isRunning: Bool { process?.isRunning == true }

    func start() {
        stopping = false
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            lastError = "Proxy not installed at \(binary.path)"
            return
        }
        publishCertificate()
        killStaleProxies()

        let p = Process()
        p.executableURL = binary
        p.arguments = [
            "-host", "127.0.0.1",
            "-port", String(Shared.proxyBase.port ?? 4443),
            "-tls-key", dir.appendingPathComponent("tls-key.pem").path,
            "-cert", dir.appendingPathComponent("tls-cert.pem").path,
            "-key-file", dir.appendingPathComponent("private-key.pem").path,
            "-session-cache", dir.appendingPathComponent("session-cache.json").path,
        ]
        let logs = dir.appendingPathComponent("logs")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let logURL = logs.appendingPathComponent("proxy.log")
        if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
        if let log = try? FileHandle(forWritingTo: logURL) {
            log.seekToEndOfFile()
            p.standardOutput = log
            p.standardError = log
        }
        p.terminationHandler = { [weak self] _ in
            guard let self, !self.stopping else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.start() }
        }
        do {
            try p.run()
            process = p
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        stopping = true
        process?.terminate()
        process = nil
    }

    /// A proxy left over from a crashed or force-quit run would hold the port.
    private func killStaleProxies() {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-f", binary.path]
        try? pkill.run()
        pkill.waitUntilExit()
        if pkill.terminationStatus == 0 { Thread.sleep(forTimeInterval: 0.5) }
    }

    /// Copies the proxy's TLS certificate (DER) into the App Group so the sandboxed widget can pin it.
    private func publishCertificate() {
        guard let pem = try? String(contentsOf: dir.appendingPathComponent("tls-cert.pem"), encoding: .utf8) else { return }
        let base64 = pem.components(separatedBy: .newlines).filter { !$0.hasPrefix("-----") }.joined()
        if let der = Data(base64Encoded: base64) {
            try? der.write(to: Shared.file("proxy-cert.der"), options: .atomic)
        }
    }
}
