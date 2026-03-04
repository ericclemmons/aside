import AppKit
import Foundation
import AsideCore

/// Captures the active application context via AppleScript.
struct ContextCapture {

    /// Capture the active window context: app name, title, URL (if browser), selected text.
    static func getActiveContext() -> ActiveContext {
        let appName = getFrontmostApp() ?? ""
        let windowTitle = getWindowTitle() ?? ""
        let url = getBrowserURL(appName: appName)
        // AX → browser JS → clipboard (universal fallback)
        let selectedText = getSelectedText()
            ?? getBrowserSelectedText(appName: appName)
            ?? getSelectedTextViaClipboard()

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

        if let text, !text.isEmpty, text != "missing value", text != "\"\"" {
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

    /// Get selected text from a Chromium browser via JavaScript.
    private static func getBrowserSelectedText(appName: String) -> String? {
        switch appName {
        case "Google Chrome", "Brave Browser", "Microsoft Edge", "Chromium", "Arc":
            return runAppleScript("""
                tell application "\(appName)"
                    tell active tab of front window
                        return execute javascript "window.getSelection().toString()"
                    end tell
                end tell
                """)
        case "Safari", "Safari Technology Preview":
            return runAppleScript("""
                tell application "\(appName)"
                    return do JavaScript "window.getSelection().toString()" in front document
                end tell
                """)
        default:
            return nil
        }
    }

    /// Universal fallback: briefly Cmd+C to grab selection via clipboard.
    private static func getSelectedTextViaClipboard() -> String? {
        let pasteboard = NSPasteboard.general
        let oldChangeCount = pasteboard.changeCount

        // Save existing clipboard
        var savedItems: [[(NSPasteboard.PasteboardType, Data)]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var pairs: [(NSPasteboard.PasteboardType, Data)] = []
            for type in item.types {
                if let data = item.data(forType: type) {
                    pairs.append((type, data))
                }
            }
            savedItems.append(pairs)
        }

        // Clear and send Cmd+C
        pasteboard.clearContents()

        let source = CGEventSource(stateID: .hidSystemState)
        let cDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
        let cUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        cDown?.flags = .maskCommand
        cUp?.flags = .maskCommand
        cDown?.post(tap: .cgAnnotatedSessionEventTap)
        cUp?.post(tap: .cgAnnotatedSessionEventTap)

        // Wait for the app to process Cmd+C
        Thread.sleep(forTimeInterval: 0.1)

        let result: String?
        if pasteboard.changeCount != oldChangeCount {
            result = pasteboard.string(forType: .string)
        } else {
            result = nil
        }

        // Restore original clipboard
        pasteboard.clearContents()
        for pairs in savedItems {
            let item = NSPasteboardItem()
            for (type, data) in pairs {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }

        guard let text = result, !text.isEmpty else { return nil }
        return text
    }
}
