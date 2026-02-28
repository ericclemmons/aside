import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Uses Apple Intelligence (on-device Foundation Models) to clean up
/// and enhance raw speech transcription output.
@available(macOS 26.0, *)
@MainActor
class TextEnhancer {

    /// Whether Apple Intelligence is available on this device.
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Enhances raw transcribed text by fixing grammar, punctuation,
    /// and formatting while preserving the original meaning.
    func enhance(_ rawText: String, systemPrompt: String) async throws -> String {
        guard TextEnhancer.isAvailable else {
            return rawText
        }

        let session = LanguageModelSession(
            instructions: systemPrompt
        )

        let response = try await session.respond(
            to: "Clean up this transcription:\n\n\(rawText)"
        )

        let enhanced = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return enhanced.isEmpty ? rawText : enhanced
    }
}
#else
/// Stub when FoundationModels SDK is unavailable (pre-macOS 26 SDK).
@MainActor
class TextEnhancer {
    static var isAvailable: Bool { false }

    func enhance(_ rawText: String, systemPrompt: String) async throws -> String {
        return rawText
    }
}
#endif
