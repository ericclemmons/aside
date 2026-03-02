import Foundation

/// Dispatches transcribed prompts to OpenCode CLI.
struct CLIDispatcher {

    /// Dispatch a prompt to OpenCode.
    /// - Parameters:
    ///   - prompt: The assembled prompt string (with context).
    ///   - server: The discovered OpenCode Desktop server to attach to.
    ///   - sessionID: Optional opencode session ID to attach to.
    ///   - filePaths: Optional file paths to attach with `-f`.
    static func dispatch(
        prompt: String,
        server: DiscoveredServer,
        sessionID: String? = nil,
        filePaths: [String] = [],
        workingDirectory: String? = nil
    ) {
        // If no session ID, create one via the API first
        var resolvedSessionID = sessionID
        if resolvedSessionID == nil || resolvedSessionID?.isEmpty == true {
            resolvedSessionID = createSession(server: server, directory: workingDirectory)
            NSLog("[Dispatch] Created new session: \(resolvedSessionID ?? "nil")")
        }

        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/\(NSUserName())"
        let opencodePath = "\(home)/.opencode/bin/opencode"

        // Pipe prompt via stdin; `run` subcommand first, then flags
        var cmd = "echo \(shellQuote(prompt)) | \(opencodePath) run"
        cmd += " --attach \(server.attachTarget)"
        if let resolvedSessionID, !resolvedSessionID.isEmpty {
            cmd += " --session \(shellQuote(resolvedSessionID))"
        }
        for path in filePaths {
            cmd += " --file=\(shellQuote(path))"
        }

        NSLog("[Dispatch] \(cmd.prefix(200))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", cmd]

        if let workingDirectory, !workingDirectory.isEmpty {
            let expandedDirectory = (workingDirectory as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: expandedDirectory, isDirectory: &isDirectory), isDirectory.boolValue {
                process.currentDirectoryURL = URL(fileURLWithPath: expandedDirectory)
            }
        }

        // Inherit user's shell environment for PATH, add auth credentials
        var env = ProcessInfo.processInfo.environment
        if let path = env["PATH"] {
            env["PATH"] = "\(home)/.opencode/bin:/opt/homebrew/bin:/usr/local/bin:\(path)"
        }
        env["OPENCODE_SERVER_USERNAME"] = server.username
        env["OPENCODE_SERVER_PASSWORD"] = server.password
        process.environment = env

        do {
            try process.run()
            NSLog("[Dispatch] opencode spawned PID: \(process.processIdentifier)")
        } catch {
            NSLog("[Dispatch] Failed to spawn opencode: \(error)")
        }
    }

    /// Create a new session on the OpenCode server via the API.
    /// Returns the session ID, or nil on failure.
    private static func createSession(server: DiscoveredServer, directory: String?) -> String? {
        let request = server.authenticatedRequest(path: "/session")
        var mutable = request
        mutable.httpMethod = "POST"
        mutable.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: String] = [:]
        if let directory, !directory.isEmpty {
            body["directory"] = directory
        }
        mutable.httpBody = try? JSONSerialization.data(withJSONObject: body)

        // Synchronous request — dispatch runs on a background context anyway
        var result: String?
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: mutable) { data, _, error in
            defer { semaphore.signal() }
            guard let data, error == nil else {
                NSLog("[Dispatch] createSession failed: \(error?.localizedDescription ?? "no data")")
                return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = json["id"] as? String {
                result = id
            }
        }.resume()
        semaphore.wait()
        return result
    }

    /// Single-quote a string for safe shell interpolation.
    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
