import Foundation

/// Captured context about the user's active window when recording started.
struct ActiveContext {
    var appName: String = ""
    var windowTitle: String = ""
    var url: String?
    var selectedText: String?
}

/// Captures the active application context via AppleScript.
struct ContextCapture {

    /// Capture the active window context: app name, title, URL (if browser), selected text.
    static func getActiveContext() -> ActiveContext {
        let appName = getFrontmostApp() ?? ""
        let windowTitle = getWindowTitle() ?? ""
        let url = getBrowserURL(appName: appName)
        let selectedText = getSelectedText()

        return ActiveContext(
            appName: appName,
            windowTitle: windowTitle,
            url: url,
            selectedText: selectedText
        )
    }

    // MARK: - Private

    private static func runAppleScript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let text, !text.isEmpty, text != "missing value" {
            return text
        }
        return nil
    }

    private static func getFrontmostApp() -> String? {
        runAppleScript(
            #"tell application "System Events" to get name of first application process whose frontmost is true"#
        )
    }

    private static func getWindowTitle() -> String? {
        runAppleScript("""
            tell application "System Events"
                set frontApp to first application process whose frontmost is true
                tell frontApp
                    if (count of windows) > 0 then
                        return name of front window
                    end if
                end tell
            end tell
            """)
    }

    private static func getBrowserURL(appName: String) -> String? {
        let script: String
        switch appName {
        case "Google Chrome", "Brave Browser", "Microsoft Edge", "Chromium", "Arc":
            script = #"tell application "\#(appName)" to return URL of active tab of front window"#
        case "Safari", "Safari Technology Preview":
            script = #"tell application "\#(appName)" to return URL of front document"#
        default:
            return nil
        }
        return runAppleScript(script)
    }

    private static func getSelectedText() -> String? {
        runAppleScript("""
            tell application "System Events"
                set frontApp to first application process whose frontmost is true
                tell frontApp
                    try
                        set focusedElem to focused UI element
                        return value of attribute "AXSelectedText" of focusedElem
                    end try
                end tell
            end tell
            """)
    }
}
