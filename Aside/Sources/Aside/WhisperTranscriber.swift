import Foundation
import AVFoundation
import Combine
import WhisperKit

// MARK: - Whisper Model Variant

enum WhisperModelVariant: String, CaseIterable, Identifiable {
    case tiny
    case base
    case small
    case largev3turbo

    var id: String { rawValue }

    /// The variant string WhisperKit expects for download.
    var whisperKitVariant: String {
        switch self {
        case .tiny: return "tiny"
        case .base: return "base"
        case .small: return "small"
        case .largev3turbo: return "large-v3-turbo"
        }
    }

    var title: String {
        switch self {
        case .tiny: return "Tiny"
        case .base: return "Base"
        case .small: return "Small"
        case .largev3turbo: return "Large v3 Turbo"
        }
    }

    var sizeDescription: String {
        switch self {
        case .tiny: return "~75 MB"
        case .base: return "~142 MB"
        case .small: return "~466 MB"
        case .largev3turbo: return "~1.5 GB"
        }
    }

    var qualityDescription: String {
        switch self {
        case .tiny: return "Fastest, good for quick notes"
        case .base: return "Balanced speed and accuracy"
        case .small: return "High accuracy, moderate speed"
        case .largev3turbo: return "Best accuracy, requires more memory"
        }
    }
}

// MARK: - WhisperModelManager

/// Manages Whisper model download state, exposed to the settings UI.
/// Supports multiple model variants with per-variant storage.
@MainActor
class WhisperModelManager: ObservableObject {
    enum ModelState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case loading
        case ready
        case error(String)
    }

    @Published var state: ModelState = .notDownloaded
    @Published var selectedVariant: WhisperModelVariant {
        didSet {
            guard oldValue != selectedVariant else { return }
            UserDefaults.standard.set(selectedVariant.rawValue, forKey: AppPreferenceKey.whisperModelVariant)
            // When switching variants, invalidate the current WhisperKit instance
            whisperKit = nil
            checkExistingModel()
        }
    }

    /// Root path where all models are stored in Application Support.
    static var modelsRootDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("com.erriclemmons.aside.app/WhisperModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Per-variant download directory to avoid collisions between models.
    var modelDirectory: URL {
        let dir = Self.modelsRootDirectory.appendingPathComponent(selectedVariant.rawValue, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var whisperKit: WhisperKit?

    init() {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.whisperModelVariant)
        self.selectedVariant = WhisperModelVariant(rawValue: raw ?? "") ?? .tiny
        checkExistingModel()
    }

    func checkExistingModel() {
        let fm = FileManager.default

        // Most reliable check: we stored the model path after a successful download
        if let storedPath = UserDefaults.standard.string(forKey: modelPathKey),
           fm.fileExists(atPath: storedPath) {
            state = .downloaded
            return
        }

        // Fallback: scan the variant directory for model files
        let modelDir = modelDirectory
        if let contents = try? fm.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil),
           contents.contains(where: { $0.hasDirectoryPath && $0.lastPathComponent.lowercased().contains("whisper") }) {
            state = .downloaded
        } else {
            let hubDir = modelDir.appendingPathComponent("huggingface")
            if fm.fileExists(atPath: hubDir.path) {
                state = .downloaded
            } else {
                state = .notDownloaded
            }
        }
    }

    /// Downloads the selected Whisper model variant. Progress updates are published.
    func downloadModel() async {
        guard case .notDownloaded = state else { return }

        state = .downloading(progress: 0)

        do {
            let modelFolder = try await WhisperKit.download(
                variant: selectedVariant.whisperKitVariant,
                downloadBase: modelDirectory,
                progressCallback: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.state = .downloading(progress: progress.fractionCompleted)
                    }
                }
            )

            // Store the path for this variant
            UserDefaults.standard.set(modelFolder.path, forKey: modelPathKey)
            state = .downloaded
        } catch {
            state = .error("Download failed: \(error.localizedDescription)")
        }
    }

    /// Initializes WhisperKit with the downloaded model. Returns the ready instance.
    func loadModel() async throws -> WhisperKit {
        if let existing = whisperKit {
            return existing
        }

        state = .loading

        // Try stored path first
        let modelPath: String? = UserDefaults.standard.string(forKey: modelPathKey)

        let config = WhisperKitConfig(
            model: selectedVariant.whisperKitVariant,
            downloadBase: modelDirectory,
            modelFolder: modelPath,
            verbose: false,
            logLevel: .none,
            prewarm: true,
            load: true,
            download: modelPath == nil
        )

        let kit = try await WhisperKit(config)
        whisperKit = kit
        state = .ready
        return kit
    }

    /// Deletes the currently selected model's files.
    func deleteModel() {
        whisperKit = nil
        try? FileManager.default.removeItem(at: modelDirectory)
        UserDefaults.standard.removeObject(forKey: modelPathKey)
        state = .notDownloaded
    }

    /// The cached WhisperKit instance, if loaded.
    var loadedKit: WhisperKit? { whisperKit }

    /// Size of the currently selected model on disk.
    var modelSizeOnDisk: String {
        guard let size = try? FileManager.default.allocatedSizeOfDirectory(at: modelDirectory), size > 0 else {
            return ""
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    /// UserDefaults key for the stored model path, unique per variant.
    private var modelPathKey: String {
        "whisperModelPath_\(selectedVariant.rawValue)"
    }
}

// MARK: - WhisperTranscriber

/// Transcriber that uses WhisperKit (OpenAI Whisper) for speech recognition.
/// Records audio into a buffer while the hotkey is held, then transcribes all at once on release.
@MainActor
class WhisperTranscriber: ObservableObject, TranscriberProtocol {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText = ""
    @Published var isEnhancing = false

    var onTranscriptionFinished: ((String) -> Void)?

    /// Custom words to bias recognition toward (names, abbreviations, etc.)
    var customWords: [String] = []

    private let audioEngine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let modelManager: WhisperModelManager

    init(modelManager: WhisperModelManager) {
        self.modelManager = modelManager
    }

    func requestPermissions() async -> Bool {
        // Whisper only needs microphone access (no SFSpeechRecognizer authorization needed)
        let micStatus = await AVCaptureDevice.requestAccess(for: .audio)
        return micStatus
    }

    func startRecording() {
        guard !isRecording else { return }

        audioBuffer = []
        transcribedText = ""
        audioLevel = 0

        do {
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            // We need 16kHz mono for Whisper. We'll convert at the end.
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                guard let self else { return }

                // Collect raw audio for later transcription
                if let channelData = buffer.floatChannelData?[0] {
                    let frameLength = Int(buffer.frameLength)
                    let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
                    self.audioBuffer.append(contentsOf: samples)

                    // Compute audio level for waveform visualization
                    if frameLength > 0 {
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
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            print("WhisperTranscriber: Failed to start recording: \(error)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false

        // Now transcribe the collected audio
        let capturedAudio = audioBuffer
        audioBuffer = []

        guard !capturedAudio.isEmpty else {
            onTranscriptionFinished?("")
            return
        }

        Task {
            await transcribeAudio(capturedAudio)
        }
    }

    private func transcribeAudio(_ samples: [Float]) async {
        do {
            let kit = try await modelManager.loadModel()

            // Resample to 16kHz mono if the input format differs
            let inputNode = audioEngine.inputNode
            let inputSampleRate = inputNode.outputFormat(forBus: 0).sampleRate
            let targetSampleRate = Double(WhisperKit.sampleRate) // 16000

            let audioForWhisper: [Float]
            if abs(inputSampleRate - targetSampleRate) > 1.0 {
                audioForWhisper = resample(samples, from: inputSampleRate, to: targetSampleRate)
            } else {
                audioForWhisper = samples
            }

            // Build decoding options with custom vocabulary as initial prompt
            var decodeOptions = DecodingOptions()
            if !customWords.isEmpty, let tokenizer = kit.tokenizer {
                let prompt = customWords.joined(separator: ", ")
                let promptTokens = tokenizer.encode(text: prompt)
                decodeOptions.promptTokens = promptTokens
            }

            let results: [TranscriptionResult] = try await kit.transcribe(audioArray: audioForWhisper, decodeOptions: decodeOptions)
            let text = results.compactMap { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

            transcribedText = text
            onTranscriptionFinished?(text)
        } catch {
            print("WhisperTranscriber: Transcription failed: \(error)")
            onTranscriptionFinished?("")
        }
    }

    /// Simple linear resampling from one sample rate to another.
    private func resample(_ samples: [Float], from sourceSampleRate: Double, to targetSampleRate: Double) -> [Float] {
        let ratio = targetSampleRate / sourceSampleRate
        let outputLength = Int(Double(samples.count) * ratio)
        var output = [Float](repeating: 0, count: outputLength)

        for i in 0..<outputLength {
            let srcIndex = Double(i) / ratio
            let srcIndexFloor = Int(srcIndex)
            let fraction = Float(srcIndex - Double(srcIndexFloor))

            if srcIndexFloor + 1 < samples.count {
                output[i] = samples[srcIndexFloor] * (1 - fraction) + samples[srcIndexFloor + 1] * fraction
            } else if srcIndexFloor < samples.count {
                output[i] = samples[srcIndexFloor]
            }
        }

        return output
    }
}

// MARK: - FileManager helper

extension FileManager {
    /// Calculates the total allocated size of a directory and its contents.
    func allocatedSizeOfDirectory(at url: URL) throws -> UInt64 {
        var totalSize: UInt64 = 0
        let enumerator = self.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            totalSize += UInt64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0)
        }
        return totalSize
    }
}
