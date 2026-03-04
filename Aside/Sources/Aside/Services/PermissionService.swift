import Foundation
import AppKit
import AVFoundation
import Speech
import AsideCore

/// Checks and requests TCC permissions.
@MainActor
final class PermissionService {

    func checkAll() -> PermissionStatus {
        PermissionStatus(
            screenRecording: checkScreenRecording(),
            microphone: checkMicrophone(),
            speechRecognition: checkSpeechRecognition(),
            accessibility: checkAccessibility()
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
            // Opens System Settings if already prompted; safe to call multiple times
            CGRequestScreenCaptureAccess()
            return checkScreenRecording()
        }
    }

    // MARK: - Individual checks

    private func checkScreenRecording() -> Bool {
        // CGPreflightScreenCaptureAccess() caches per-process — useless for polling.
        // Instead, check if we can read window names from other processes.
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }
        let myPID = Int(ProcessInfo.processInfo.processIdentifier)
        for window in windowList {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int,
                  pid != myPID else { continue }
            // Without screen recording, kCGWindowName is absent for other apps
            if window.keys.contains(kCGWindowName as String) {
                return true
            }
        }
        return false
    }

    private func checkMicrophone() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func checkSpeechRecognition() -> Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    private func checkAccessibility() -> Bool {
        // AXIsProcessTrustedWithOptions(nil) caches per-process — useless for polling.
        // Create a .listenOnly tap (mouseMoved) to avoid conflict with HotkeyManager's .defaultTap.
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.mouseMoved.rawValue),
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        )
        guard let tap else { return false }
        CFMachPortInvalidate(tap)
        return true
    }
}
