import Foundation
import Combine

// MARK: - TranscriptionRecord

struct TranscriptionRecord: Codable, Identifiable {
    let id: UUID
    let text: String
    let timestamp: Date
    let engine: String       // "dictation" or "whisper"
    let wasEnhanced: Bool

    init(text: String, engine: TranscriptionEngine, wasEnhanced: Bool) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.engine = engine.rawValue
        self.wasEnhanced = wasEnhanced
    }
}

// MARK: - TranscriptionHistoryManager

/// Manages a persistent history of the last 50 transcriptions.
/// Stored as a JSON file in Application Support.
@MainActor
class TranscriptionHistoryManager: ObservableObject {
    @Published private(set) var records: [TranscriptionRecord] = []

    private static let maxRecords = 50

    private static var historyFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("com.erriclemmons.aside.app", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    init() {
        loadFromDisk()
    }

    /// Adds a new transcription record. Keeps only the most recent 50.
    func addRecord(_ record: TranscriptionRecord) {
        guard !record.text.isEmpty else { return }
        records.insert(record, at: 0)
        if records.count > Self.maxRecords {
            records = Array(records.prefix(Self.maxRecords))
        }
        saveToDisk()
    }

    /// Deletes a single record by ID.
    func deleteRecord(id: UUID) {
        records.removeAll { $0.id == id }
        saveToDisk()
    }

    /// Clears all history.
    func clearHistory() {
        records.removeAll()
        saveToDisk()
    }

    // MARK: - Persistence

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: Self.historyFileURL, options: .atomic)
        } catch {
            print("TranscriptionHistory: Failed to save: \(error)")
        }
    }

    private func loadFromDisk() {
        let url = Self.historyFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            records = try JSONDecoder().decode([TranscriptionRecord].self, from: data)
        } catch {
            print("TranscriptionHistory: Failed to load: \(error)")
            records = []
        }
    }
}

// MARK: - Static Relative Date Formatting

extension Date {
    /// Returns a static relative string like "Just now", "3 min ago", "2 hr ago", "Yesterday", etc.
    var relativeString: String {
        let now = Date()
        let seconds = Int(now.timeIntervalSince(self))

        if seconds < 60 {
            return "Just now"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) min ago"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) hr ago"
        }

        let days = hours / 24
        if days == 1 {
            return "Yesterday"
        }
        if days < 7 {
            return "\(days) days ago"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}
