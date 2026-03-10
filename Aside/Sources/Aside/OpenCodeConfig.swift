import Foundation
import AsideCore

/// Discovers and tracks a running OpenCode Desktop server via `ps eww`.
@MainActor
class OpenCodeConfig: ObservableObject {
    @Published var server: DiscoveredServer?

    var isConnected: Bool { server != nil }

    /// Scan running processes for `opencode-cli serve` and extract port + credentials.
    func discover() {
        Task.detached(priority: .utility) { [weak self] in
            let found = Self.findDesktopServer()
            await MainActor.run { [weak self] in
                self?.server = found
            }
        }
    }

    /// Find OpenCode Desktop's bundled CLI serve process.
    nonisolated static func findDesktopServer() -> DiscoveredServer? {
        return findServer()
    }

    nonisolated static func findServer() -> DiscoveredServer? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["ewwA", "-o", "pid,command"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            NSLog("[OpenCodeConfig] ps failed: \(error)")
            return nil
        }

        // Read data BEFORE waitUntilExit to avoid deadlock when output > 64KB pipe buffer
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)

        for line in output.components(separatedBy: "\n") {
            // Look for OpenCode Desktop's bundled CLI serve process
            guard line.contains("OpenCode.app") && line.contains("opencode-cli") && line.contains("serve") else { continue }
            guard !line.contains("grep") else { continue }

            guard let port = extractFlag(from: line, flag: "--port").flatMap({ Int($0) }) else { continue }
            let host = extractFlag(from: line, flag: "--hostname") ?? "127.0.0.1"
            let username = extractEnvVar(from: line, name: "OPENCODE_SERVER_USERNAME") ?? "opencode"
            guard let password = extractEnvVar(from: line, name: "OPENCODE_SERVER_PASSWORD") else { continue }

            // Extract CLI path: everything after PID up to "opencode-cli" + that suffix
            let cliPath = extractCliPath(from: line) ?? ""

            return DiscoveredServer(host: host, port: port, username: username, password: password, cliPath: cliPath)
        }

        return nil
    }

    /// Extract the value following a --flag from a command string.
    private nonisolated static func extractFlag(from line: String, flag: String) -> String? {
        // Handle --flag=value
        if let range = line.range(of: "\(flag)=") {
            let after = line[range.upperBound...]
            let value = after.prefix(while: { !$0.isWhitespace })
            return value.isEmpty ? nil : String(value)
        }
        // Handle --flag value
        guard let range = line.range(of: flag) else { return nil }
        let after = line[range.upperBound...].drop(while: { $0.isWhitespace })
        let value = after.prefix(while: { !$0.isWhitespace })
        return value.isEmpty ? nil : String(value)
    }

    /// Extract the opencode-cli binary path from a ps output line.
    /// Line format: "  PID /path/to/opencode-cli --flags ..."
    private nonisolated static func extractCliPath(from line: String) -> String? {
        // Find the path that ends with "opencode-cli"
        guard let range = line.range(of: "/", options: []),
              let endRange = line.range(of: "opencode-cli") else { return nil }
        let path = String(line[range.lowerBound..<endRange.upperBound])
        return path.isEmpty ? nil : path
    }

    /// Extract an environment variable value from ps eww output.
    /// ps eww appends env vars as KEY=VALUE pairs separated by spaces after the command.
    private nonisolated static func extractEnvVar(from line: String, name: String) -> String? {
        let pattern = "\(name)="
        guard let range = line.range(of: pattern) else { return nil }
        let after = line[range.upperBound...]
        let value = after.prefix(while: { !$0.isWhitespace })
        return value.isEmpty ? nil : String(value)
    }
}
