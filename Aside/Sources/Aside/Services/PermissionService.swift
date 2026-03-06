import Foundation
import AppKit
import AVFoundation
import Speech
import AsideCore

/// Checks and requests TCC permissions.
@MainActor
final class PermissionService {

    private var accessibilityObserver: NSObjectProtocol?
    private var onAccessibilityChange: (() -> Void)?

    /// After the first CGRequestScreenCaptureAccess() call, subsequent calls
    /// return live state without showing a prompt. We use this for polling.
    private var screenRecordingRequested = false

    /// Register a callback for when accessibility permission changes.
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
            screenRecording: checkScreenRecording(),
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            speechRecognition: SFSpeechRecognizer.authorizationStatus() == .authorized,
            accessibility: checkAccessibility()
        )
    }

    func request(_ permission: Permission) async -> Bool {
        switch permission {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            return checkAccessibility()
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
            if !screenRecordingRequested {
                screenRecordingRequested = true
                CGRequestScreenCaptureAccess()
            }
            return checkScreenRecording()
        }
    }

    /// Quick check: is screen recording currently working?
    var hasScreenRecording: Bool { checkScreenRecording() }

    // MARK: - Capability tests

    /// Test if we can create the same kind of event tap HotkeyManager needs.
    /// This is the ground truth — if this works, the hotkey will work.
    private func checkAccessibility() -> Bool {
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        )
        guard let tap else { return false }
        CFMachPortInvalidate(tap)
        return true
    }

    /// Check screen recording permission.
    /// CGPreflightScreenCaptureAccess is correct at process launch time on Sequoia.
    /// It does NOT update mid-process — permission changes require app restart.
    private func checkScreenRecording() -> Bool {
        CGPreflightScreenCaptureAccess()
    }
}
