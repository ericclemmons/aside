import Foundation
import AppKit
import AsideCore

/// Manages window screenshot capture using CGWindowList APIs.
@MainActor
final class ScreenCaptureService: ScreenCaptureServiceProtocol {
    private var pickerController: WindowPickerController?
    private var onCapture: ((String) -> Void)?

    /// Reference to the overlay window so we can promote it above picker panels.
    var overlayWindow: RecordingOverlayWindow?

    func startCapture(onCapture: @escaping (String) -> Void) {
        self.onCapture = onCapture

        let controller = WindowPickerController()
        controller.onCapture = onCapture
        pickerController = controller

        // Promote waveform overlay above picker panels
        overlayWindow?.level = NSWindow.Level(Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)

        controller.show()
    }

    func stopCapture() {
        pickerController?.dismiss()
        pickerController = nil
        onCapture = nil

        // Restore waveform overlay level
        overlayWindow?.level = .floating
    }

    func deleteFiles(_ paths: [String]) {
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
