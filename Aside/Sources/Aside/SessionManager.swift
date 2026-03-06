import Foundation
import AsideCore

/// Fetches and manages opencode sessions.
@MainActor
class SessionManager: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var selectedSessionID: String?
    @Published var currentProjectDirectory: String?

    let config: OpenCodeConfig

    init(config: OpenCodeConfig) {
        self.config = config
    }

    /// The currently selected session, if any.
    var selectedSession: Session? {
        guard let id = selectedSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    /// Fetches sessions and current project from the OpenCode server.
    func refresh() async {
        guard let server = config.server else {
            sessions = []
            currentProjectDirectory = nil
            return
        }
        async let fetchedSessions = Self.fetchSessions(server: server)
        async let fetchedProject = Self.fetchCurrentProjectDirectory(server: server)
        sessions = await fetchedSessions
        currentProjectDirectory = await fetchedProject
    }

    nonisolated static func abbreviateHome(in path: String) -> String {
        Session.abbreviateHome(in: path)
    }

    private static func fetchCurrentProjectDirectory(server: DiscoveredServer) async -> String? {
        let request = server.authenticatedRequest(path: "/project/current")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let path = json["path"] as? String, !path.isEmpty else { return nil }
            return path
        } catch {
            print("[SessionManager] Failed to fetch current project: \(error)")
            return nil
        }
    }

    private static func fetchSessions(server: DiscoveredServer) async -> [Session] {
        let request = server.authenticatedRequest(path: "/session")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }

            var sessions = json.compactMap { obj -> Session? in
                guard let id = obj["id"] as? String else { return nil }
                let name = (obj["title"] as? String) ?? id
                // Timestamps are Unix milliseconds, nested under "time"
                let time = obj["time"] as? [String: Any]
                let updatedMs = (time?["updated"] as? Double) ?? (time?["created"] as? Double) ?? 0
                let updatedAt = Date(timeIntervalSince1970: updatedMs / 1000.0)
                let directory = obj["directory"] as? String
                return Session(id: id, name: name, updatedAt: updatedAt, directory: directory)
            }

            // Sort by most recent first
            sessions.sort { $0.updatedAt > $1.updatedAt }
            return sessions
        } catch {
            print("[SessionManager] Failed to fetch sessions: \(error)")
            return []
        }
    }
}
