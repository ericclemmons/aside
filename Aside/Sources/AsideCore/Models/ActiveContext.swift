import Foundation

public struct ActiveContext: Equatable, Sendable {
    public var appName: String
    public var windowTitle: String
    public var url: String?
    public var selectedText: String?

    public init(appName: String = "", windowTitle: String = "", url: String? = nil, selectedText: String? = nil) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.selectedText = selectedText
    }
}
