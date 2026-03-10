import Foundation
import AsideCore

/// Dispatches transcribed prompts to OpenCode Desktop's server via `opencode-cli run`.
struct CLIDispatcher {

    /// Dispatch a prompt to OpenCode.
    /// - Parameters:
    ///   - prompt: The assembled prompt string (with context).
    ///   - server: The OpenCode Desktop server to dispatch to.
    ///   - sessionID: Optional opencode session ID to continue.
    ///   - filePaths: Optional file paths to attach with `--file`.
    static func dispatch(
        prompt: String,
        server: DiscoveredServer,
        sessionID: String? = nil,
        filePaths: [String] = [],
        workingDirectory: String? = nil
    ) {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/\(NSUserName())"
        // Prefer OpenCode Desktop's bundled CLI, fall back to ~/.opencode/bin/opencode
        let opencodePath = server.cliPath.isEmpty ? "\(home)/.opencode/bin/opencode" : server.cliPath

        // Build arguments: run --attach <url> [--session id] [--dir dir] [--file=path] -- <prompt>
        var args = ["run", "--attach", server.attachTarget]

        if let sessionID, !sessionID.isEmpty {
            args += ["--session", sessionID]
        }

        if let workingDirectory, !workingDirectory.isEmpty {
            args += ["--dir", workingDirectory]
        }

        for path in filePaths {
            args.append("--file=\(path)")
        }

        args += ["--", prompt]

        NSLog("[Dispatch] %@ %@", opencodePath, args.joined(separator: " "))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: opencodePath)
        process.arguments = args

        if let workingDirectory, !workingDirectory.isEmpty {
            let expandedDirectory = (workingDirectory as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: expandedDirectory, isDirectory: &isDirectory), isDirectory.boolValue {
                process.currentDirectoryURL = URL(fileURLWithPath: expandedDirectory)
            }
        }

        // Inherit user's shell environment for PATH + server credentials
        var env = ProcessInfo.processInfo.environment
        if let path = env["PATH"] {
            env["PATH"] = "\(home)/.opencode/bin:/opt/homebrew/bin:/usr/local/bin:\(path)"
        }
        if !server.username.isEmpty {
            env["OPENCODE_SERVER_USERNAME"] = server.username
        }
        if !server.password.isEmpty {
            env["OPENCODE_SERVER_PASSWORD"] = server.password
        }
        process.environment = env

        // Capture stderr to log errors
        let errPipe = Pipe()
        process.standardError = errPipe

        do {
            try process.run()
            NSLog("[Dispatch] opencode spawned PID: %d", process.processIdentifier)

            // Log stderr asynchronously
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                    NSLog("[Dispatch] stderr: %@", str)
                }
            }
        } catch {
            NSLog("[Dispatch] Failed to spawn opencode: %@", error.localizedDescription)
        }
    }
}
