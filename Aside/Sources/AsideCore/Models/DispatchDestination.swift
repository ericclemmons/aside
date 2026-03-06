import Foundation

public struct DispatchDestination: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case sectionHeader
        case newSessionWorkspace
        case existingSession
    }

    public let id: String
    public let kind: Kind
    public let label: String
    public let detail: String?
    public let time: String?
    public let sessionID: String?
    public let workingDirectory: String?

    public init(id: String, kind: Kind, label: String, detail: String?, time: String?, sessionID: String?, workingDirectory: String?) {
        self.id = id
        self.kind = kind
        self.label = label
        self.detail = detail
        self.time = time
        self.sessionID = sessionID
        self.workingDirectory = workingDirectory
    }

    public var isSelectable: Bool {
        kind != .sectionHeader
    }

    public static func sectionHeader(_ title: String) -> DispatchDestination {
        DispatchDestination(
            id: "header-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))",
            kind: .sectionHeader,
            label: title,
            detail: nil,
            time: nil,
            sessionID: nil,
            workingDirectory: nil
        )
    }

    public static func newOpenCodeWorkspace(displayDirectory: String, workingDirectory: String) -> DispatchDestination {
        DispatchDestination(
            id: "opencode-new-\(workingDirectory)",
            kind: .newSessionWorkspace,
            label: "New Session",
            detail: displayDirectory,
            time: nil,
            sessionID: nil,
            workingDirectory: workingDirectory
        )
    }

    public static func openCodeSession(_ session: Session) -> DispatchDestination {
        let displayDirectory = session.directory.map { Session.abbreviateHome(in: $0) }
        return DispatchDestination(
            id: "opencode-\(session.id)",
            kind: .existingSession,
            label: session.name,
            detail: displayDirectory,
            time: session.timeString,
            sessionID: session.id,
            workingDirectory: nil
        )
    }
}
