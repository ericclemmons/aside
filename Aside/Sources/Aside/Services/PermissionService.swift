import Foundation
import AppKit
import AVFoundation
import Speech
import AsideCore

/// Checks and requests TCC permissions.
///
/// Standard APIs (AXIsProcessTrusted, CGPreflightScreenCaptureAccess) cache
/// per-process and return stale values — especially with ad-hoc signing where
/// each build has a different cdhash. Instead, we test actual capabilities:
/// - Accessibility: try creating the same .defaultTap CGEvent tap the hotkey needs
/// - Screen recording: try reading window names from other processes
/// - Mic/speech: standard status APIs work reliably for these
@MainActor
final class PermissionService {

    private var accessibilityObserver: NSObjectProtocol?
    private var onAccessibilityChange: (() -> Void)?

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
            CGRequestScreenCaptureAccess()
            return checkScreenRecording()
        }
    }

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

    /// Test if we can read window names from other processes.
    /// Without screen recording permission, kCGWindowName is absent for other apps.
    private func checkScreenRecording() -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }
        let myPID = Int(ProcessInfo.processInfo.processIdentifier)
        for window in windowList {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int,
                  pid != myPID else { continue }
            if window.keys.contains(kCGWindowName as String) {
                return true
            }
        }
        return false
    }
}
