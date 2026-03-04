import Foundation
import AsideCore

/// Manages the screencapture process for window screenshots.
@MainActor
final class ScreenCaptureService {
    private var process: Process?
    private var onCapture: ((String) -> Void)?

    func startCapture(onCapture: @escaping (String) -> Void) {
        self.onCapture = onCapture
        spawnCapture()
    }

    func stopCapture() {
        process?.terminate()
        process = nil
        onCapture = nil
    }

    func deleteFiles(_ paths: [String]) {
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private func spawnCapture() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let timestamp = formatter.string(from: Date())
        let tempPath = "/tmp/com.ericclemmons.Aside-\(timestamp).png"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-Wo", tempPath]
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.process = nil
                if FileManager.default.fileExists(atPath: tempPath) {
                    self.onCapture?(tempPath)
                    // Re-spawn if still capturing
                    if self.onCapture != nil {
                        self.spawnCapture()
                    }
                }
            }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            NSLog("[ScreenCapture] Failed to spawn: \(error)")
        }
    }
}
