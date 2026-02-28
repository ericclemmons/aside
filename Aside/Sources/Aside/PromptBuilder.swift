import Foundation

/// Builds a prompt string from the user's transcription and captured context.
///
/// Example output:
///   [Context: Chrome — https://github.com/org/repo/issues/42]
///   [Selected: "TypeError: Cannot read property 'map' of undefined"]
///
///   Fix this bug
struct PromptBuilder {

    static func buildPrompt(transcription: String, context: ActiveContext?) -> String {
        var parts: [String] = []

        if let context {
            let appInfo: String
            if let url = context.url, !url.isEmpty {
                appInfo = "\(context.appName) — \(url)"
            } else {
                appInfo = context.appName
            }

            if !appInfo.isEmpty {
                parts.append("[Context: \(appInfo)]")
            }

            if let selectedText = context.selectedText, !selectedText.isEmpty {
                // Truncate very long selections
                let selected = selectedText.count > 500
                    ? String(selectedText.prefix(500)) + "..."
                    : selectedText
                parts.append("[Selected: \"\(selected)\"]")
            }
        }

        if !parts.isEmpty {
            parts.append("") // blank line between context and prompt
        }

        parts.append(transcription)

        return parts.joined(separator: "\n")
    }
}
