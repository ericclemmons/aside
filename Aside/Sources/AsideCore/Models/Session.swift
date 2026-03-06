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

    /// Relative time string: today="3:38 PM", yesterday="Yesterday", this week="Mon", older="Mar 1"
    public var timeString: String {
        let cal = Calendar.current
        if cal.isDateInToday(updatedAt) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: updatedAt)
        }
        if cal.isDateInYesterday(updatedAt) {
            return "Yesterday"
        }
        let daysAgo = cal.dateComponents([.day], from: updatedAt, to: Date()).day ?? 99
        if daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: updatedAt)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
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
