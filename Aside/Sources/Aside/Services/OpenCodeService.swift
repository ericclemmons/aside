import Foundation
import AsideCore

/// Discovers OpenCode Desktop's internal server via `ps eww` and provides
/// server + session management for dispatch.
@MainActor
final class OpenCodeService {
    let config = OpenCodeConfig()
    private lazy var sessionManager = SessionManager(config: config)
    private var discoveryTimer: Timer?

    var server: DiscoveredServer? { config.server }

    /// Poll for OpenCode Desktop's `opencode-cli serve` process every 2 seconds.
    func startDiscovery(onChange: @escaping (DiscoveredServer?) -> Void) {
        config.discover()
        onChange(config.server)

        discoveryTimer?.invalidate()
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.config.discover()
                onChange(self.config.server)
            }
        }
    }

    func stopDiscovery() {
        discoveryTimer?.invalidate()
        discoveryTimer = nil
    }

    func refreshSessions() async -> (sessions: [Session], projectDirectory: String?) {
        await sessionManager.refresh()
        return (sessionManager.sessions, sessionManager.currentProjectDirectory)
    }
}
