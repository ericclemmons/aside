import Foundation

/// Which CLI tool to dispatch transcriptions to.
enum CLITarget: String, CaseIterable, Identifiable {
    case claude
    case opencode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .opencode: return "OpenCode"
        }
    }

    var description: String {
        switch self {
        case .claude: return "Dispatches to `claude` CLI"
        case .opencode: return "Dispatches to `opencode` CLI"
        }
    }
}

/// Dispatches transcribed prompts to CLI tools (claude or opencode).
struct CLIDispatcher {

    /// Dispatch a prompt to the selected CLI target.
    /// - Parameters:
    ///   - prompt: The assembled prompt string (with context).
    ///   - target: Which CLI to use (claude or opencode).
    ///   - sessionID: Optional opencode session ID to attach to.
    static func dispatch(prompt: String, target: CLITarget, sessionID: String? = nil) {
        let escaped = prompt.replacingOccurrences(of: "'", with: "'\\''")

        let shellCmd: String
        switch target {
        case .claude:
            shellCmd = "claude --print '\(escaped)'"
        case .opencode:
            if let sessionID, !sessionID.isEmpty {
                let escapedSession = sessionID.replacingOccurrences(of: "'", with: "'\\''")
                shellCmd = "opencode --attach localhost:4096 --session '\(escapedSession)' run '\(escaped)'"
            } else {
                shellCmd = "opencode run '\(escaped)'"
            }
        }

        print("Dispatching to \(target.rawValue): \(shellCmd)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", shellCmd]

        // Inherit user's shell environment for PATH
        var env = ProcessInfo.processInfo.environment
        // Also source the user's shell profile for tools installed via homebrew etc.
        if let path = env["PATH"] {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(path)"
        }
        process.environment = env

        do {
            try process.run()
            print("\(target.rawValue) spawned with PID: \(process.processIdentifier)")
        } catch {
            print("Failed to spawn \(target.rawValue): \(error)")
        }
    }
}
