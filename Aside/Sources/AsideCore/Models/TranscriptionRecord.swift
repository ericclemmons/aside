import Foundation

public struct TranscriptionRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let timestamp: Date
    public let engine: String       // "dictation" or "whisper"
    public let wasEnhanced: Bool

    public init(text: String, engine: TranscriptionEngine, wasEnhanced: Bool) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.engine = engine.rawValue
        self.wasEnhanced = wasEnhanced
    }

    public init(id: UUID, text: String, timestamp: Date, engine: String, wasEnhanced: Bool) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.engine = engine
        self.wasEnhanced = wasEnhanced
    }
}
