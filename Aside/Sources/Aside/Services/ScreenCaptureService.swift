import Foundation
import AppKit
import AsideCore

/// Manages screencapture subprocess for interactive screen/window capture.
/// Uses `screencapture -io` — interactive mode, omits shadow. SPACE toggles window/selection.
@MainActor
final class ScreenCaptureService: ScreenCaptureServiceProtocol {
    private var process: Process?
    private var onCapture: ((String) -> Void)?

    func startCapture(onCapture: @escaping (String) -> Void) {
        self.onCapture = onCapture
        spawnCapture()
    }

    func stopCapture() {
        process?.interrupt()  // SIGINT lets screencapture restore the cursor
        process = nil
        onCapture = nil
        // screencapture may not restore cursor before exiting — nudge the cursor
        // to force the window server to recalculate it from the window under it.
        let pos = NSEvent.mouseLocation
        if let screen = NSScreen.main {
            CGWarpMouseCursorPosition(CGPoint(x: pos.x, y: screen.frame.height - pos.y))
        }
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
        proc.arguments = ["-io", tempPath]
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
