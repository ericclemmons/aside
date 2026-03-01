import Foundation

/// Builds a prompt string from the user's transcription and captured context.
///
/// Example output:
///   > Selected text here
///   > - https://example.com/the/page/im/on
///
///   Fix this bug
struct PromptBuilder {

    static func buildPrompt(transcription: String, context: ActiveContext?) -> String {
        var parts: [String] = []

        if let context {
            // Selected text as blockquote
            if let selectedText = context.selectedText, !selectedText.isEmpty {
                let selected = selectedText.count > 500
                    ? String(selectedText.prefix(500)) + "..."
                    : selectedText
                let quoted = selected.components(separatedBy: CharacterSet.newlines)
                    .map { "> \($0)" }
                    .joined(separator: "\n")
                parts.append(quoted)
            }

            // URL as blockquoted reference
            if let url = context.url, !url.isEmpty {
                parts.append("> - \(url)")
            }
        }

        if !parts.isEmpty {
            parts.append("") // blank line between context and prompt
        }

        parts.append(transcription)

        return parts.joined(separator: "\n")
    }
}
