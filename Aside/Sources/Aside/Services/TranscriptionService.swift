import Foundation
import AsideCore

/// Wraps SpeechTranscriber, WhisperTranscriber, and ParakeetTranscriber behind a unified interface.
@MainActor
final class TranscriptionService {
    private let speechTranscriber = SpeechTranscriber()
    private var whisperTranscriber: WhisperTranscriber?
    private var parakeetTranscriber: ParakeetTranscriber?
    let whisperModelManager = WhisperModelManager()
    let parakeetModelManager = ParakeetModelManager()

    var onTranscriptionUpdate: ((String, Float) -> Void)?
    var onTranscriptionFinished: ((String) -> Void)?

    private var updateTimer: Timer?
    private var activeEngine: TranscriptionEngine = .dictation

    /// Which transcriber is actually running (may differ from activeEngine if model wasn't ready)
    private enum ActiveTranscriber { case speech, whisper, parakeet }
    private var activeTranscriber: ActiveTranscriber = .speech

    var isRecording: Bool {
        switch activeTranscriber {
        case .whisper: return whisperTranscriber?.isRecording ?? false
        case .parakeet: return parakeetTranscriber?.isRecording ?? false
        case .speech: return speechTranscriber.isRecording
        }
    }

    var audioLevel: Float {
        switch activeTranscriber {
        case .whisper: return whisperTranscriber?.audioLevel ?? 0
        case .parakeet: return parakeetTranscriber?.audioLevel ?? 0
        case .speech: return speechTranscriber.audioLevel
        }
    }

    var transcribedText: String {
        switch activeTranscriber {
        case .whisper: return whisperTranscriber?.transcribedText ?? ""
        case .parakeet: return parakeetTranscriber?.transcribedText ?? ""
        case .speech: return speechTranscriber.transcribedText
        }
    }

    func startRecording(engine: TranscriptionEngine, customWords: [String]) {
        activeEngine = engine
        NSLog("[TranscriptionService] startRecording engine=%@ parakeetReady=%d whisperReady=%d",
              engine.rawValue, isParakeetReady ? 1 : 0, isWhisperReady ? 1 : 0)

        switch engine {
        case .whisper where isWhisperReady:
            activeTranscriber = .whisper
            let whisper = whisperTranscriber ?? WhisperTranscriber(modelManager: whisperModelManager)
            whisperTranscriber = whisper
            whisper.customWords = customWords
            whisper.onTranscriptionFinished = { [weak self] text in
                self?.onTranscriptionFinished?(text)
            }
            whisper.startRecording()
            startUpdatePolling { [weak whisper] in
                guard let w = whisper else { return (0, "") }
                return (w.audioLevel, w.transcribedText)
            }

        case .parakeet where isParakeetReady:
            activeTranscriber = .parakeet
            let parakeet = parakeetTranscriber ?? ParakeetTranscriber(modelManager: parakeetModelManager)
            parakeetTranscriber = parakeet
            parakeet.customWords = customWords
            parakeet.onTranscriptionFinished = { [weak self] text in
                self?.onTranscriptionFinished?(text)
            }
            parakeet.startRecording()
            startUpdatePolling { [weak parakeet] in
                guard let p = parakeet else { return (0, "") }
                return (p.audioLevel, p.transcribedText)
            }

        default:
            activeTranscriber = .speech
            speechTranscriber.customWords = customWords
            speechTranscriber.onTranscriptionFinished = { [weak self] text in
                self?.onTranscriptionFinished?(text)
            }
            speechTranscriber.startRecording()
            startUpdatePolling { [weak self] in
                guard let s = self?.speechTranscriber else { return (0, "") }
                return (s.audioLevel, s.transcribedText)
            }
        }
    }

    func stopRecording() {
        stopUpdatePolling()
        switch activeTranscriber {
        case .whisper:
            whisperTranscriber?.stopRecording()
        case .parakeet:
            parakeetTranscriber?.stopRecording()
        case .speech:
            speechTranscriber.stopRecording()
        }
    }

    func cancelRecording() {
        stopUpdatePolling()
        switch activeTranscriber {
        case .whisper:
            whisperTranscriber?.onTranscriptionFinished = nil
            whisperTranscriber?.stopRecording()
        case .parakeet:
            parakeetTranscriber?.onTranscriptionFinished = nil
            parakeetTranscriber?.stopRecording()
        case .speech:
            speechTranscriber.onTranscriptionFinished = nil
            speechTranscriber.stopRecording()
        }
        onTranscriptionUpdate = nil
        onTranscriptionFinished = nil
    }

    private var isWhisperReady: Bool {
        switch whisperModelManager.state {
        case .downloaded, .ready, .loading:
            return true
        default:
            return false
        }
    }

    private var isParakeetReady: Bool {
        switch parakeetModelManager.state {
        case .downloaded, .ready, .loading:
            return true
        default:
            return false
        }
    }

    private func startUpdatePolling(levels: @escaping () -> (Float, String)) {
        var lastText = ""
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let (level, text) = levels()
            if text != lastText || level != 0 {
                lastText = text
                self.onTranscriptionUpdate?(text, level)
            }
        }
    }

    private func stopUpdatePolling() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
}
