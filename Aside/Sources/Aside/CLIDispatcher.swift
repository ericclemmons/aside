import Foundation

/// Dispatches transcribed prompts to OpenCode via its HTTP API.
struct CLIDispatcher {

    /// Dispatch a prompt to OpenCode.
    /// - Parameters:
    ///   - prompt: The assembled prompt string (with context).
    ///   - server: The discovered OpenCode Desktop server to attach to.
    ///   - sessionID: Optional opencode session ID. If nil, creates a new session.
    ///   - filePaths: Optional file paths (screenshots) to attach.
    ///   - workingDirectory: Working directory for new sessions.
    static func dispatch(
        prompt: String,
        server: DiscoveredServer,
        sessionID: String? = nil,
        filePaths: [String] = [],
        workingDirectory: String? = nil
    ) {
        Task.detached(priority: .userInitiated) {
            do {
                // Resolve session ID — create one if needed
                let resolvedID: String
                if let sessionID, !sessionID.isEmpty {
                    resolvedID = sessionID
                } else {
                    resolvedID = try await createSession(server: server)
                    NSLog("[Dispatch] Created session: %@", resolvedID)
                }

                // Build parts array
                var parts: [[String: Any]] = [
                    ["type": "text", "text": prompt]
                ]

                // Attach screenshots as file parts with data URIs
                for path in filePaths {
                    guard let data = FileManager.default.contents(atPath: path) else { continue }
                    let base64 = data.base64EncodedString()
                    let mime = path.hasSuffix(".png") ? "image/png" : "image/jpeg"
                    let filename = (path as NSString).lastPathComponent
                    parts.append([
                        "type": "file",
                        "mime": mime,
                        "filename": filename,
                        "url": "data:\(mime);base64,\(base64)"
                    ])
                }

                let body: [String: Any] = ["parts": parts]

                // POST /session/:id/prompt_async
                var request = server.authenticatedRequest(path: "/session/\(resolvedID)/prompt_async")
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                NSLog("[Dispatch] prompt_async → %d (session: %@, files: %d)", status, resolvedID, filePaths.count)

                if status != 204 {
                    NSLog("[Dispatch] Unexpected status: %d", status)
                }
            } catch {
                NSLog("[Dispatch] Failed: %@", error.localizedDescription)
            }
        }
    }

    /// Create a new session on the OpenCode server.
    private static func createSession(server: DiscoveredServer) async throws -> String {
        var request = server.authenticatedRequest(path: "/session")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [:] as [String: Any])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            throw DispatchError.sessionCreateFailed(status: status)
        }
        return id
    }

    enum DispatchError: Error, LocalizedError {
        case sessionCreateFailed(status: Int)
        var errorDescription: String? {
            switch self {
            case .sessionCreateFailed(let status): return "Failed to create session (HTTP \(status))"
            }
        }
    }
}
