import Foundation

/// A discovered OpenCode Desktop server instance.
struct DiscoveredServer {
    let host: String
    let port: Int
    let username: String
    let password: String

    var attachTarget: String { "http://\(host):\(port)" }
    var baseURL: URL { URL(string: "http://\(host):\(port)")! }

    /// Build a URLRequest with Basic auth for the given API path.
    func authenticatedRequest(path: String) -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        let credentials = "\(username):\(password)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        return request
    }
}

/// Discovers and tracks a running OpenCode Desktop server via `ps eww`.
@MainActor
class OpenCodeConfig: ObservableObject {
    @Published var server: DiscoveredServer?

    var isConnected: Bool { server != nil }

    /// Scan running processes for `opencode-cli serve` and extract port + credentials.
    func discover() {
        Task.detached(priority: .utility) { [weak self] in
            let found = Self.findServer()
            await MainActor.run { [weak self] in
                self?.server = found
            }
        }
    }

    private nonisolated static func findServer() -> DiscoveredServer? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["eww", "-o", "pid,command"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("[OpenCodeConfig] ps failed: \(error)")
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)

        for line in output.components(separatedBy: "\n") {
            // Look for opencode-cli serve processes
            guard line.contains("opencode-cli") && line.contains("serve") else { continue }
            // Skip grep/ps artifacts
            guard !line.contains("grep") else { continue }

            // Extract port from --port flag
            guard let port = extractFlag(from: line, flag: "--port").flatMap({ Int($0) }) else { continue }

            // Extract host from --hostname flag (default to 127.0.0.1)
            let host = extractFlag(from: line, flag: "--hostname") ?? "127.0.0.1"

            // Extract credentials from environment variables in the ps eww output
            let username = extractEnvVar(from: line, name: "OPENCODE_SERVER_USERNAME") ?? "opencode"
            guard let password = extractEnvVar(from: line, name: "OPENCODE_SERVER_PASSWORD") else { continue }

            return DiscoveredServer(host: host, port: port, username: username, password: password)
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
