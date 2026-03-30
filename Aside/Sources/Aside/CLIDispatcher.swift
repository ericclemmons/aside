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
        workingDirectory: String? = nil,
        onSuccess: (() -> Void)? = nil,
        onFailure: ((String) -> Void)? = nil
    ) {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/\(NSUserName())"
        // Prefer OpenCode Desktop's bundled CLI, fall back to opencode on PATH
        let opencodePath = server.cliPath.isEmpty ? "\(home)/.opencode/bin/opencode" : server.cliPath

        // Global flags before subcommand, then run -- <prompt>
        var args = ["--attach", server.attachTarget]

        if let sessionID, !sessionID.isEmpty {
            args += ["--session", sessionID]
        }

        if let workingDirectory, !workingDirectory.isEmpty {
            args += ["--dir", workingDirectory]
        }

        args.append("run")

        for path in filePaths {
            args.append("--file=\(path)")
        }

        args.append("--")
        args += prompt.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        // Log the full command to a file for debugging
        let debugCmd = args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
        var envPrefix = ""
        if !server.username.isEmpty { envPrefix += "OPENCODE_SERVER_USERNAME=\(server.username) " }
        if !server.password.isEmpty { envPrefix += "OPENCODE_SERVER_PASSWORD=\(server.password) " }
        let logLine = "[\(ISO8601DateFormatter().string(from: Date()))] \(envPrefix)\(opencodePath) \(debugCmd)\n"
        NSLog("[Dispatch] %@", logLine.trimmingCharacters(in: .newlines))
        let logPath = (ProcessInfo.processInfo.environment["HOME"] ?? "/tmp") + "/aside-dispatch.log"
        if let data = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fh = FileHandle(forWritingAtPath: logPath) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    fh.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logPath, contents: data)
            }
        }

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

            // Log stderr and detect failures asynchronously
            var stderrOutput = ""
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                    NSLog("[Dispatch] stderr: %@", str)
                    stderrOutput += str + "\n"
                }
            }

            // Monitor process exit to report failures
            process.terminationHandler = { proc in
                let status = proc.terminationStatus
                if status != 0 {
                    let reason = stderrOutput.isEmpty
                        ? "opencode-cli exited with code \(status)"
                        : stderrOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    NSLog("[Dispatch] Process exited with status %d: %@", status, reason)
                    DispatchQueue.main.async {
                        onFailure?(reason)
                    }
                } else {
                    NSLog("[Dispatch] Process exited successfully")
                    DispatchQueue.main.async {
                        onSuccess?()
                    }
                }
            }
        } catch {
            NSLog("[Dispatch] Failed to spawn opencode: %@", error.localizedDescription)
            onFailure?("Failed to spawn opencode: \(error.localizedDescription)")
        }
    }
}
