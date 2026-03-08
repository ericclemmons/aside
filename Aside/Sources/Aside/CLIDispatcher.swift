import Foundation
import AsideCore

/// Dispatches transcribed prompts to OpenCode Desktop's server via `opencode --attach`.
struct CLIDispatcher {

    /// Dispatch a prompt to OpenCode.
    /// - Parameters:
    ///   - prompt: The assembled prompt string (with context).
    ///   - server: The Aside opencode server to attach to.
    ///   - sessionID: Optional opencode session ID to continue.
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

        // Build shell command: echo '<prompt>' | opencode [global-flags] run [run-flags]
        // --file is a `run` subcommand flag, so it must come after `run`.
        var globalFlags = " --attach \(server.attachTarget)"

        if let sessionID, !sessionID.isEmpty {
            globalFlags += " --session \(shellQuote(sessionID))"
        }

        if let workingDirectory, !workingDirectory.isEmpty {
            globalFlags += " --dir \(shellQuote(workingDirectory))"
        }

        var runFlags = ""
        for path in filePaths {
            runFlags += " --file=\(shellQuote(path))"
        }

        let cmd = "echo \(shellQuote(prompt)) | \(opencodePath)\(globalFlags) run\(runFlags)"
        NSLog("[Dispatch] %@", String(cmd.prefix(300)))

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

    /// Single-quote a string for safe shell interpolation.
    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
