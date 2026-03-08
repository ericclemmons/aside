import Foundation
import AsideCore

/// Manages screencapture subprocess for interactive screen/window capture.
/// Uses `screencapture -iow` — interactive mode defaulting to window capture, omits shadow.
@MainActor
final class ScreenCaptureService: ScreenCaptureServiceProtocol {
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
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let tempPath = "/tmp/com.ericclemmons.Aside-\(timestamp).png"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-iow", tempPath]
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.process = nil
                if FileManager.default.fileExists(atPath: tempPath) {
                    self.onCapture?(tempPath)
                    // Re-spawn for additional captures while still recording
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
