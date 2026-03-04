import Foundation

@MainActor
public protocol TranscriptionServiceProtocol {
    func startRecording(engine: TranscriptionEngine, customWords: [String])
    func stopRecording()
    var isRecording: Bool { get }
    var audioLevel: Float { get }
    var transcribedText: String { get }
}
