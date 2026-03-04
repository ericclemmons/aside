import Foundation
import AsideCore

/// Wraps both SpeechTranscriber and WhisperTranscriber behind a unified interface.
@MainActor
final class TranscriptionService {
    private let speechTranscriber = SpeechTranscriber()
    private var whisperTranscriber: WhisperTranscriber?
    let whisperModelManager = WhisperModelManager()

    var onTranscriptionUpdate: ((String, Float) -> Void)?
    var onTranscriptionFinished: ((String) -> Void)?

    private var updateTimer: Timer?
    private var activeEngine: TranscriptionEngine = .dictation

    var isRecording: Bool {
        if activeEngine == .whisper, let w = whisperTranscriber { return w.isRecording }
        return speechTranscriber.isRecording
    }

    var audioLevel: Float {
        if activeEngine == .whisper, let w = whisperTranscriber { return w.audioLevel }
        return speechTranscriber.audioLevel
    }

    var transcribedText: String {
        if activeEngine == .whisper, let w = whisperTranscriber { return w.transcribedText }
        return speechTranscriber.transcribedText
    }

    func startRecording(engine: TranscriptionEngine, customWords: [String]) {
        activeEngine = engine

        if engine == .whisper, isWhisperReady {
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
        } else {
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
        if activeEngine == .whisper, isWhisperReady {
            whisperTranscriber?.stopRecording()
        } else {
            speechTranscriber.stopRecording()
        }
    }

    func cancelRecording() {
        stopUpdatePolling()
        if activeEngine == .whisper, isWhisperReady {
            whisperTranscriber?.onTranscriptionFinished = nil
            whisperTranscriber?.stopRecording()
        } else {
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
