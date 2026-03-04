import Foundation
import AppKit
import AVFoundation
import Speech
import AsideCore

/// Checks and requests TCC permissions using standard Apple APIs.
@MainActor
final class PermissionService {

    private var accessibilityObserver: NSObjectProtocol?
    private var onAccessibilityChange: (() -> Void)?

    /// Register a callback for when accessibility permission changes.
    /// Uses the `com.apple.accessibility.api` distributed notification.
    func observeAccessibilityChanges(_ handler: @escaping () -> Void) {
        onAccessibilityChange = handler
        accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onAccessibilityChange?()
        }
    }

    deinit {
        if let observer = accessibilityObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    func checkAll() -> PermissionStatus {
        PermissionStatus(
            screenRecording: CGPreflightScreenCaptureAccess(),
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            speechRecognition: SFSpeechRecognizer.authorizationStatus() == .authorized,
            accessibility: AXIsProcessTrusted()
        )
    }

    func request(_ permission: Permission) async -> Bool {
        switch permission {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        case .microphone:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    cont.resume(returning: granted)
                }
            }
        case .speechRecognition:
            return await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status == .authorized)
                }
            }
        case .screenRecording:
            CGRequestScreenCaptureAccess()
            return CGPreflightScreenCaptureAccess()
        }
    }
}
