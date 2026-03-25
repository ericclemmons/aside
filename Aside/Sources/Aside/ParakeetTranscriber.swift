import Foundation
import AVFoundation
import Combine
import FluidAudio
import AsideCore

// MARK: - ParakeetModelManager

/// Manages Parakeet model download state via FluidAudio.
@MainActor
class ParakeetModelManager: ObservableObject {
    enum ModelState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case loading
        case ready
        case error(String)
    }

    @Published var state: ModelState = .notDownloaded
    @Published private(set) var modelSizeOnDiskCached: String = ""

    private var asrManager: AsrManager?
    private var loadTask: Task<Void, any Error>?
    private var downloadTask: Task<Void, Never>?

    var modelDirectory: URL {
        AsrModels.defaultCacheDirectory(for: .v3)
    }

    init() {
        checkExistingModel()
    }

    func checkExistingModel() {
        let dir = AsrModels.defaultCacheDirectory(for: .v3)
        if AsrModels.modelsExist(at: dir, version: .v3) {
            state = .downloaded
            refreshModelSizeOnDisk()
        } else {
            state = .notDownloaded
            modelSizeOnDiskCached = ""
        }
    }

    func downloadModel() async {
        guard case .notDownloaded = state else { return }
        state = .downloading(progress: -1)

        let task = Task {
            do {
                try await AsrModels.download(version: .v3)
                guard !Task.isCancelled else { return }
                state = .downloaded
                refreshModelSizeOnDisk()
            } catch {
                guard !Task.isCancelled else { return }
                state = .error("Download failed: \(error.localizedDescription)")
            }
        }
        downloadTask = task
        await task.value
        downloadTask = nil
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        let dir = modelDirectory
        try? FileManager.default.removeItem(at: dir)
        state = .notDownloaded
        modelSizeOnDiskCached = ""
    }

    func loadModel() async throws -> AsrManager {
        if let existing = asrManager {
            state = .ready
            return existing
        }

        if let existing = loadTask {
            try await existing.value
            return asrManager!
        }

        state = .loading

        let task = Task<Void, any Error> {
            let dir = AsrModels.defaultCacheDirectory(for: .v3)
            let asrModels = try await AsrModels.load(from: dir, version: .v3)
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: asrModels)
            await MainActor.run { asrManager = manager }
        }
        loadTask = task

        do {
            try await task.value
            loadTask = nil
            state = .ready
            refreshModelSizeOnDisk()
            return asrManager!
        } catch {
            loadTask = nil
            state = .error("Load failed: \(error.localizedDescription)")
            throw error
        }
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let manager = asrManager else {
            throw ParakeetError.modelNotLoaded
        }
        let result = try await manager.transcribe(audioURL, source: .system)
        return result.text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func deleteModel() {
        asrManager = nil
        loadTask?.cancel()
        loadTask = nil
        let dir = modelDirectory
        try? FileManager.default.removeItem(at: dir)
        state = .notDownloaded
        modelSizeOnDiskCached = ""
    }

    var modelSizeOnDisk: String { modelSizeOnDiskCached }

    private func refreshModelSizeOnDisk() {
        let dir = modelDirectory
        Task.detached(priority: .utility) {
            let sizeString: String
            if let size = try? FileManager.default.allocatedSizeOfDirectory(at: dir), size > 0 {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useMB, .useGB]
                formatter.countStyle = .file
                sizeString = formatter.string(fromByteCount: Int64(size))
            } else {
                sizeString = ""
            }
            await MainActor.run { [sizeString] in
                self.modelSizeOnDiskCached = sizeString
            }
        }
    }
}

enum ParakeetError: LocalizedError {
    case modelNotLoaded
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Parakeet model is not loaded."
        case .emptyAudio: return "No audio was recorded."
        }
    }
}

// MARK: - ParakeetTranscriber

/// Transcriber using FluidAudio's Parakeet ASR.
/// Records audio into a buffer, writes a temp WAV, then transcribes on release.
@MainActor
class ParakeetTranscriber: ObservableObject, TranscriberProtocol {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText = ""
    @Published var isEnhancing = false

    var onTranscriptionFinished: ((String) -> Void)?
    var customWords: [String] = []

    private let modelManager: ParakeetModelManager
    private let audioEngine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private var inputSampleRate: Double = 16000
    private var transcriptionTask: Task<Void, Never>?

    init(modelManager: ParakeetModelManager) {
        self.modelManager = modelManager
    }

    func requestPermissions() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func startRecording() {
        guard !isRecording else {
            NSLog("[Parakeet] startRecording called but already recording")
            return
        }
        transcriptionTask?.cancel()
        transcriptionTask = nil

        audioBuffer = []
        audioBuffer.reserveCapacity(48000 * 60)
        transcribedText = ""
        audioLevel = 0

        NSLog("[Parakeet] Starting recording")
        do {
            // Reset so inputNode re-acquires the current default input device
            audioEngine.reset()
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputSampleRate = recordingFormat.sampleRate

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                guard let self else { return }
                if let channelData = buffer.floatChannelData?[0] {
                    let frameLength = Int(buffer.frameLength)
                    let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
                    self.audioBuffer.append(contentsOf: samples)

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
            NSLog("ParakeetTranscriber: Failed to start recording: \(error)")
        }
    }

    func stopRecording() {
        guard isRecording else {
            NSLog("[Parakeet] stopRecording called but not recording")
            return
        }

        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false

        let capturedAudio = audioBuffer
        let sampleRate = inputSampleRate
        audioBuffer = []

        NSLog("[Parakeet] Stopped recording, captured %d samples at %.0f Hz (%.1f sec)",
              capturedAudio.count, sampleRate, Double(capturedAudio.count) / sampleRate)

        guard !capturedAudio.isEmpty else {
            NSLog("[Parakeet] No audio captured, finishing with empty text")
            onTranscriptionFinished?("")
            return
        }

        transcriptionTask = Task { [weak self] in
            await self?.transcribeAudio(capturedAudio, sampleRate: sampleRate)
        }
    }

    private func transcribeAudio(_ samples: [Float], sampleRate: Double) async {
        guard !Task.isCancelled else {
            NSLog("[Parakeet] transcribeAudio: task cancelled before start")
            return
        }
        do {
            NSLog("[Parakeet] Loading model...")
            _ = try await modelManager.loadModel()
            guard !Task.isCancelled else {
                NSLog("[Parakeet] transcribeAudio: task cancelled after model load")
                return
            }

            NSLog("[Parakeet] Writing WAV file...")
            let tempURL = try writeWAVFile(samples: samples, sampleRate: sampleRate)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            NSLog("[Parakeet] Transcribing audio...")
            let text = try await modelManager.transcribe(audioURL: tempURL)
            guard !Task.isCancelled else {
                NSLog("[Parakeet] transcribeAudio: task cancelled after transcription")
                return
            }

            NSLog("[Parakeet] Transcription result: '%@' (%d chars)", text, text.count)
            transcribedText = text
            onTranscriptionFinished?(text)
        } catch {
            guard !Task.isCancelled else {
                NSLog("[Parakeet] transcribeAudio: task cancelled during error handling")
                return
            }
            NSLog("[Parakeet] Transcription failed: %@", error.localizedDescription)
            onTranscriptionFinished?("")
        }
    }

    private func writeWAVFile(samples: [Float], sampleRate: Double) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("aside_parakeet_\(UUID().uuidString).wav")

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw ParakeetError.emptyAudio
        }

        buffer.frameLength = frameCount
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }

        let file = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        try file.write(from: buffer)
        return tempURL
    }
}
