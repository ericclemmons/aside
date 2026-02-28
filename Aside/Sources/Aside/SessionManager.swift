import Foundation

/// An opencode session.
struct Session: Identifiable {
    let id: String
    let name: String
    let lastActive: String
}

/// Fetches and manages opencode sessions.
@MainActor
class SessionManager: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var selectedSessionID: String?

    /// The currently selected session, if any.
    var selectedSession: Session? {
        guard let id = selectedSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    /// Fetches sessions from `opencode session list --format json`.
    func refresh() async {
        let fetched = await Self.fetchSessions()
        sessions = fetched
    }

    private static func fetchSessions() async -> [Session] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", "opencode session list --format json"]

                var env = ProcessInfo.processInfo.environment
                if let path = env["PATH"] {
                    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(path)"
                }
                process.environment = env

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continuation.resume(returning: [])
                    return
                }

                guard process.terminationStatus == 0 else {
                    continuation.resume(returning: [])
                    return
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    continuation.resume(returning: [])
                    return
                }

                var sessions = json.compactMap { obj -> Session? in
                    guard let id = obj["id"] as? String else { return nil }
                    let name = (obj["title"] as? String) ?? id
                    let lastActive = (obj["updated_at"] as? String) ?? (obj["created_at"] as? String) ?? ""
                    return Session(id: id, name: name, lastActive: lastActive)
                }

                // Sort by lastActive descending (most recent first)
                sessions.sort { a, b in
                    a.lastActive > b.lastActive
                }

                continuation.resume(returning: sessions)
            }
        }
    }
}
