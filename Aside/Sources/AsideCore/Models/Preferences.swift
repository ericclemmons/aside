import Foundation

public enum TranscriptionEngine: String, CaseIterable, Identifiable, Sendable {
    case dictation
    case whisper
    case parakeet

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dictation: return "Direct Dictation"
        case .whisper: return "Whisper (OpenAI)"
        case .parakeet: return "Parakeet (NVIDIA)"
        }
    }

    public var description: String {
        switch self {
        case .dictation: return "Uses Apple's built-in speech recognition. Works immediately with no setup."
        case .whisper: return "Uses OpenAI's Whisper model running locally on your Mac. Requires a one-time download."
        case .parakeet: return "Uses NVIDIA's Parakeet model running locally. Requires a one-time download."
        }
    }
}

public enum HotkeyMode: String, CaseIterable, Identifiable, Sendable {
    case holdToTalk
    case toggle

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .holdToTalk: return "Hold to Type"
        case .toggle: return "Tap to Agent"
        }
    }

    public var description: String {
        switch self {
        case .holdToTalk: return "Hold Right ⌥ to record — transcription is typed into the active field on release."
        case .toggle: return "Tap Right ⌥ to start recording, tap again to stop — then choose where to send the prompt."
        }
    }
}

public enum EnhancementMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case appleIntelligence

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: return "Off"
        case .appleIntelligence: return "Apple Intelligence"
        }
    }
}

public enum AppPreferenceKey {
    public static let transcriptionEngine = "transcriptionEngine"
    public static let enhancementMode = "enhancementMode"
    public static let enhancementSystemPrompt = "enhancementSystemPrompt"
    public static let hotkeyMode = "hotkeyMode"
    public static let whisperModelVariant = "whisperModelVariant"

    public static let defaultEnhancementPrompt = """
        You are Aside, a speech-to-text transcription assistant. Your only job is to \
        enhance raw transcription output. Fix punctuation, add missing commas, correct \
        capitalization, and improve formatting. Do not alter the meaning, tone, or \
        substance of the text. Do not add, remove, or rephrase any content. Do not \
        add commentary or explanations. Return only the cleaned-up text.
        """
}
