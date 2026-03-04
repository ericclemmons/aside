import Foundation
import AppKit
import ScreenCaptureKit

/// Captures the frontmost non-Aside window using ScreenCaptureKit.
/// Same TCC scope as our capability test — no subprocess, no extra TCC dialog.
@MainActor
final class ScreenCaptureService {
    private var onCapture: ((String) -> Void)?

    func startCapture(onCapture: @escaping (String) -> Void) {
        self.onCapture = onCapture
        Task { await captureTopmostWindow() }
    }

    func stopCapture() {
        onCapture = nil
    }

    func deleteFiles(_ paths: [String]) {
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private func captureTopmostWindow() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let asidePID = ProcessInfo.processInfo.processIdentifier

            // Find frontmost non-Aside window that's reasonably sized
            guard let targetWindow = content.windows.first(where: { window in
                window.owningApplication?.processID != asidePID
                && window.frame.width >= 100
                && window.frame.height >= 100
                && window.isOnScreen
            }) else {
                NSLog("[ScreenCapture] No suitable window found")
                return
            }

            let filter = SCContentFilter(desktopIndependentWindow: targetWindow)
            let config = SCStreamConfiguration()
            config.width = Int(targetWindow.frame.width) * 2  // Retina
            config.height = Int(targetWindow.frame.height) * 2
            config.captureResolution = .best
            config.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )

            // Save as PNG
            let timestamp = Int(Date().timeIntervalSince1970)
            let tempPath = "/tmp/com.ericclemmons.Aside-\(timestamp).png"
            let url = URL(fileURLWithPath: tempPath)

            let rep = NSBitmapImageRep(cgImage: image)
            guard let pngData = rep.representation(using: .png, properties: [:]) else {
                NSLog("[ScreenCapture] Failed to create PNG data")
                return
            }
            try pngData.write(to: url)

            NSLog("[ScreenCapture] Captured window to %@", tempPath)
            onCapture?(tempPath)
        } catch {
            NSLog("[ScreenCapture] Capture failed: %@", error.localizedDescription)
        }
    }
}
