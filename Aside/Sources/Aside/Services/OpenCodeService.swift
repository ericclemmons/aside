import Foundation
import AsideCore

/// Runs its own `opencode serve` on port 45103 (ASIDE in 1337-speak)
/// and provides a fixed DiscoveredServer for dispatch + session queries.
@MainActor
final class OpenCodeService {
    static let port = 45103

    let config = OpenCodeConfig()
    private lazy var sessionManager = SessionManager(config: config)
    private var serverProcess: Process?

    var server: DiscoveredServer? { config.server }

    /// Start `opencode serve --port 45103` and set the fixed server.
    func startDiscovery(onChange: @escaping (DiscoveredServer?) -> Void) {
        startServer()
        let s = DiscoveredServer(host: "127.0.0.1", port: Self.port, username: "", password: "")
        config.server = s
        onChange(s)
    }

    func stopDiscovery() {
        serverProcess?.terminate()
        serverProcess = nil
    }

    func refreshSessions() async -> (sessions: [Session], projectDirectory: String?) {
        await sessionManager.refresh()
        return (sessionManager.sessions, sessionManager.currentProjectDirectory)
    }

    private func startServer() {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/\(NSUserName())"
        let opencodePath = "\(home)/.opencode/bin/opencode"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: opencodePath)
        proc.arguments = ["serve", "--port", "\(Self.port)"]

        var env = ProcessInfo.processInfo.environment
        if let path = env["PATH"] {
            env["PATH"] = "\(home)/.opencode/bin:/opt/homebrew/bin:/usr/local/bin:\(path)"
        }
        proc.environment = env

        // Log server output
        let errPipe = Pipe()
        proc.standardError = errPipe
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty else { return }
            NSLog("[OpenCodeServer] %@", str)
        }

        do {
            try proc.run()
            serverProcess = proc
            NSLog("[OpenCodeServer] Started on port %d, PID %d", Self.port, proc.processIdentifier)
        } catch {
            NSLog("[OpenCodeServer] Failed to start: %@", error.localizedDescription)
        }
    }
}
