import Foundation
import AsideCore

/// Merged OpenCodeConfig + SessionManager functionality.
@MainActor
final class OpenCodeService {
    let config = OpenCodeConfig()
    private lazy var sessionManager = SessionManager(config: config)
    private var discoveryTimer: Timer?

    var server: DiscoveredServer? { config.server }

    func startDiscovery(onChange: @escaping (DiscoveredServer?) -> Void) {
        // Initial discovery
        config.discover()
        onChange(config.server)

        // Periodic discovery every 5 seconds
        discoveryTimer?.invalidate()
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
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
