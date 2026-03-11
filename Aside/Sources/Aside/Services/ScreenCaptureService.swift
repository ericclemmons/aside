import Foundation
import AppKit
import AsideCore

/// Manages screencapture subprocess for interactive screen/window capture.
/// Uses `screencapture -ioW` — interactive mode starting in window capture, omits shadow. SPACE toggles to selection.
@MainActor
final class ScreenCaptureService: ScreenCaptureServiceProtocol {
    private var process: Process?
    private var onCapture: ((String) -> Void)?

    func startCapture(onCapture: @escaping (String) -> Void) {
        self.onCapture = onCapture
        spawnCapture()
    }

    func stopCapture() {
        let proc = process
        process = nil
        onCapture = nil
        proc?.interrupt()  // SIGINT lets screencapture restore the cursor
        // Wait for screencapture to exit, then nudge cursor to reset the crosshair.
        // A 2-step warp (offset + restore) forces the window server to recalculate.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let pos = NSEvent.mouseLocation
            guard let screen = NSScreen.main else { return }
            let flipped = CGPoint(x: pos.x, y: screen.frame.height - pos.y)
            CGWarpMouseCursorPosition(CGPoint(x: flipped.x + 1, y: flipped.y))
            CGWarpMouseCursorPosition(flipped)
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
        proc.arguments = ["-ioW", tempPath]
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
