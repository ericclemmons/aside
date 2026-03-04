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

    /// Formatted time string, e.g. "3:38 PM"
    public var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: updatedAt)
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
