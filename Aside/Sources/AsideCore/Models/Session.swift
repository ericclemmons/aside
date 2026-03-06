import Foundation

public struct Session: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let updatedAt: Date
    public let directory: String?

    public init(id: String, name: String, updatedAt: Date, directory: String?) {
        self.id = id
        self.name = name
        self.updatedAt = updatedAt
        self.directory = directory
    }

    /// Relative time string: "2m ago", "3h ago", "1d ago", "2w ago"
    public var timeString: String {
        let seconds = Int(Date().timeIntervalSince(updatedAt))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        if seconds < 604800 { return "\(seconds / 86400)d ago" }
        return "\(seconds / 604800)w ago"
    }

    /// Replace the user's home directory with ~ for display.
    public static func abbreviateHome(in path: String) -> String {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/\(NSUserName())"
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
