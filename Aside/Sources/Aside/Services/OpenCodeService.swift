import Foundation
import AsideCore

/// Manages Aside's own opencode server (port 4096) and discovers OpenCode Desktop's server.
@MainActor
final class OpenCodeService {
    let config = OpenCodeConfig()
    private lazy var sessionManager = SessionManager(config: config)
    private var discoveryTimer: Timer?
    private var serverProcess: Process?

    static let asidePort = 4096

    var server: DiscoveredServer? { config.server }

    // MARK: - Aside Server (port 4096)

    /// Start Aside's own `opencode serve` on port 4096 (no auth).
    func startAsideServer(onReady: @escaping (DiscoveredServer?) -> Void) {
        // Kill any existing process
        stopServer()

        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/\(NSUserName())"
        let opencodePath = "\(home)/.opencode/bin/opencode"

        guard FileManager.default.fileExists(atPath: opencodePath) else {
            NSLog("[OpenCodeService] opencode not found at %@", opencodePath)
            onReady(nil)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: opencodePath)
        process.arguments = ["serve"]

        var env = ProcessInfo.processInfo.environment
        env["PORT"] = String(Self.asidePort)
        if let path = env["PATH"] {
            env["PATH"] = "\(home)/.opencode/bin:/opt/homebrew/bin:/usr/local/bin:\(path)"
        }
        process.environment = env

        // Set working directory to home
        process.currentDirectoryURL = URL(fileURLWithPath: home)

        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice

        // Log stderr
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                NSLog("[OpenCodeService] serve stderr: %@", str)
            }
        }

        do {
            try process.run()
            serverProcess = process
            NSLog("[OpenCodeService] Started opencode serve on port %d (PID %d)", Self.asidePort, process.processIdentifier)

            // Poll until server is responsive
            pollUntilReady(onReady: onReady)
        } catch {
            NSLog("[OpenCodeService] Failed to start opencode serve: %@", error.localizedDescription)
            onReady(nil)
        }
    }

    private func pollUntilReady(attempts: Int = 0, onReady: @escaping (DiscoveredServer?) -> Void) {
        let server = DiscoveredServer(host: "127.0.0.1", port: Self.asidePort, username: "", password: "")
        let url = server.baseURL.appendingPathComponent("/session")
        var request = URLRequest(url: url)
        request.timeoutInterval = 1

        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    NSLog("[OpenCodeService] Aside server ready on port %d", Self.asidePort)
                    onReady(server)
                    return
                }
            } catch {
                // Not ready yet
            }

            if attempts < 30 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.pollUntilReady(attempts: attempts + 1, onReady: onReady)
                }
            } else {
                NSLog("[OpenCodeService] Aside server failed to become ready after 15s")
                onReady(nil)
            }
        }
    }

    // MARK: - OpenCode Desktop Discovery

    /// Poll for OpenCode Desktop's `opencode-cli serve` process every 2 seconds.
    func startDesktopDiscovery(onChange: @escaping (DiscoveredServer?) -> Void) {
        let found = OpenCodeConfig.findDesktopServer()
        onChange(found)

        discoveryTimer?.invalidate()
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                let server = OpenCodeConfig.findDesktopServer()
                onChange(server)
            }
        }
    }

    func stopDiscovery() {
        discoveryTimer?.invalidate()
        discoveryTimer = nil
    }

    func stopServer() {
        if let process = serverProcess, process.isRunning {
            NSLog("[OpenCodeService] Terminating opencode serve (PID %d)", process.processIdentifier)
            process.terminate()
        }
        serverProcess = nil
    }

    func refreshSessions(server: DiscoveredServer? = nil) async -> (sessions: [Session], projectDirectory: String?) {
        await sessionManager.refresh(server: server)
        return (sessionManager.sessions, sessionManager.currentProjectDirectory)
    }
}
