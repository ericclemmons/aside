import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
class SpeechTranscriber: ObservableObject, TranscriberProtocol {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText = ""
    @Published var isEnhancing = false

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var finalizeTimeoutTask: Task<Void, Never>?
    /// Incremented each session to discard stale callbacks from cancelled tasks.
    private var sessionID: UInt64 = 0

    var onTranscriptionFinished: ((String) -> Void)?

    /// Custom words to hint the recognizer toward (names, abbreviations, etc.)
    var customWords: [String] = []

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    }

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }

        let micStatus = await AVCaptureDevice.requestAccess(for: .audio)
        return micStatus
    }

    // MARK: - Recording lifecycle

    func startRecording() {
        // Re-create recognizer if previous one is gone or stuck
        if speechRecognizer == nil {
            speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        }
        guard let recognizer = speechRecognizer else {
            NSLog("[SpeechTranscriber] Recognizer is nil")
            return
        }

        // Cancel any pending finalization — a new session supersedes it
        finalizeTimeoutTask?.cancel()
        finalizeTimeoutTask = nil

        // Do NOT explicitly cancel the old recognition task here.
        // SFSpeechRecognizer handles the transition internally when
        // we create a new task, and avoids the "recognizer unavailable
        // after cancel" state that breaks tap-to-dispatch.

        sessionID &+= 1
        let currentSession = sessionID
        transcribedText = ""
        audioLevel = 0

        // New recognition request — the audio tap feeds whichever request
        // is assigned to self.recognitionRequest
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if !customWords.isEmpty {
            request.contextualStrings = customWords
        }
        recognitionRequest = request

        // Start audio engine if not already running (reused across tap-to-dispatch)
        if !audioEngine.isRunning {
            do {
                try installTapAndStartEngine()
            } catch {
                NSLog("[SpeechTranscriber] Failed to start audio engine: %@", error.localizedDescription)
                recognitionRequest = nil
                return
            }
        }

        // Create new recognition task — implicitly supersedes any old task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                NSLog("[SpeechTranscriber] Got result: isFinal=%d, session=%llu, text='%@'",
                      result.isFinal ? 1 : 0, currentSession, text)
                Task { @MainActor in
                    guard self.sessionID == currentSession else { return }
                    self.transcribedText = text
                    if result.isFinal {
                        self.finishRecognition(session: currentSession, text: text)
                    }
                }
            }

            if let error {
                let nsError = error as NSError
                NSLog("[SpeechTranscriber] Recognition error: session=%llu domain=%@ code=%d desc=%@",
                      currentSession, nsError.domain, nsError.code, nsError.localizedDescription)
                Task { @MainActor in
                    guard self.sessionID == currentSession else { return }
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                        self.finishRecognition(session: currentSession, text: "")
                    } else {
                        self.finishRecognition(session: currentSession, text: self.transcribedText)
                    }
                }
            }
        }

        isRecording = true
        NSLog("[SpeechTranscriber] Recording started (session=%llu)", sessionID)
    }

    func stopRecording() {
        let session = sessionID
        isRecording = false

        // Signal end of audio — recognizer will finalize
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        let currentText = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)

        if currentText.isEmpty {
            // TAP-TO-DISPATCH: No text → deliver empty result synchronously.
            // The callback may trigger startRecording immediately (same call stack),
            // which creates a new recognition task before the recognizer enters
            // a cancelled/unavailable state.
            NSLog("[SpeechTranscriber] stopRecording: no text, delivering empty result (session=%llu)", session)
            onTranscriptionFinished?("")

            // If the callback didn't start a new recording, clean up
            if !isRecording {
                recognitionTask?.cancel()
                recognitionTask = nil
                stopEngine()
            }
        } else {
            // HOLD-TO-TYPE: Has text → wait for recognizer to deliver final result.
            // The isFinal callback usually arrives within ~200ms. Timeout at 900ms.
            NSLog("[SpeechTranscriber] stopRecording: has text, waiting for final (session=%llu)", session)
            finalizeTimeoutTask?.cancel()
            finalizeTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(900))
                await MainActor.run {
                    guard let self, self.sessionID == session else { return }
                    NSLog("[SpeechTranscriber] Finalization timeout (session=%llu)", session)
                    self.finishRecognition(session: session, text: self.transcribedText)
                }
            }
        }
    }

    // MARK: - Private

    private func finishRecognition(session: UInt64, text: String) {
        guard session == sessionID else { return }

        NSLog("[SpeechTranscriber] Finishing recognition (session=%llu, text='%@')", session, text)

        finalizeTimeoutTask?.cancel()
        finalizeTimeoutTask = nil

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        onTranscriptionFinished?(text.trimmingCharacters(in: .whitespacesAndNewlines))

        // If no new recording was started by the callback, shut down audio
        if !isRecording {
            stopEngine()
        }
    }

    private func installTapAndStartEngine() throws {
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            // Feed audio to the current request (nil between sessions → no-op)
            self.recognitionRequest?.append(buffer)

            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            if frameLength == 0 { return }

            var rms: Float = 0
            for i in 0..<frameLength {
                rms += channelData[i] * channelData[i]
            }
            rms = sqrt(rms / Float(frameLength))
            let normalized = min(rms * 20, 1.0)

            Task { @MainActor [weak self] in
                self?.audioLevel = normalized
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        NSLog("[SpeechTranscriber] Audio engine started")
    }

    private func stopEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
            NSLog("[SpeechTranscriber] Audio engine stopped")
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}
