import Foundation
import AsideCore

/// Discovers OpenCode Desktop's server and manages sessions.
@MainActor
final class OpenCodeService {
    let config = OpenCodeConfig()
    private lazy var sessionManager = SessionManager(config: config)
    private var discoveryTimer: Timer?

    var server: DiscoveredServer? { config.server }

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

    func refreshSessions(server: DiscoveredServer? = nil) async -> (sessions: [Session], projectDirectory: String?) {
        await sessionManager.refresh(server: server)
        return (sessionManager.sessions, sessionManager.currentProjectDirectory)
    }
}
