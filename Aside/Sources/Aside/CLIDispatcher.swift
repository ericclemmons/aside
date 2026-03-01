import Foundation

/// Dispatches transcribed prompts to OpenCode CLI.
struct CLIDispatcher {

    /// Dispatch a prompt to OpenCode.
    /// - Parameters:
    ///   - prompt: The assembled prompt string (with context).
    ///   - sessionID: Optional opencode session ID to attach to.
    static func dispatch(prompt: String, sessionID: String? = nil) {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/\(NSUserName())"
        let opencodePath = "\(home)/.opencode/bin/opencode"

        // Build the shell command with proper quoting
        var cmd = "\(opencodePath) --attach localhost:4096"
        if let sessionID, !sessionID.isEmpty {
            cmd += " --session \(shellQuote(sessionID))"
        }
        cmd += " run \(shellQuote(prompt))"

        print("[Dispatch] \(cmd.prefix(200))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", cmd]

        // Inherit user's shell environment for PATH
        var env = ProcessInfo.processInfo.environment
        if let path = env["PATH"] {
            env["PATH"] = "\(home)/.opencode/bin:/opt/homebrew/bin:/usr/local/bin:\(path)"
        }
        process.environment = env

        do {
            try process.run()
            print("[Dispatch] opencode spawned PID: \(process.processIdentifier)")
        } catch {
            print("[Dispatch] Failed to spawn opencode: \(error)")
        }
    }

    /// Single-quote a string for safe shell interpolation.
    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
