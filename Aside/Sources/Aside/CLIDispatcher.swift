import Foundation
import AsideCore

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
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/\(NSUserName())"
        let opencodePath = "\(home)/.opencode/bin/opencode"

        // Build args array: opencode run [flags] <prompt>
        var args = ["run"]

        if let sessionID, !sessionID.isEmpty {
            // Existing session: attach to server + resume session
            args += ["--attach", server.attachTarget]
            args += ["--session", sessionID]
        } else if let workingDirectory, !workingDirectory.isEmpty {
            // New session: attach to server, specify remote dir
            args += ["--attach", server.attachTarget]
            args += ["--dir", workingDirectory]
        } else {
            // Fallback: attach without session (may fail)
            args += ["--attach", server.attachTarget]
        }

        for path in filePaths {
            args += ["--file=\(path)"]
        }

        // Prompt as positional argument (not piped via stdin)
        args.append(prompt)

        NSLog("[Dispatch] %@ %@", opencodePath, args.joined(separator: " ").prefix(300).description)

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

        // Inherit user's shell environment for PATH, add auth credentials
        var env = ProcessInfo.processInfo.environment
        if let path = env["PATH"] {
            env["PATH"] = "\(home)/.opencode/bin:/opt/homebrew/bin:/usr/local/bin:\(path)"
        }
        env["OPENCODE_SERVER_USERNAME"] = server.username
        env["OPENCODE_SERVER_PASSWORD"] = server.password
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
