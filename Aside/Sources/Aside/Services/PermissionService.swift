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
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
    }

    func openSystemPreferences(for permission: Permission) {
        let urlString: String
        switch permission {
        case .screenRecording:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .speechRecognition:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Individual checks

    private func checkScreenRecording() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    private func checkMicrophone() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func checkSpeechRecognition() -> Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    private func checkAccessibility() -> Bool {
        // Create and immediately invalidate a CGEvent tap — this is the most accurate check
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        )
        if let tap {
            CFMachPortInvalidate(tap)
            return true
        }
        return false
    }
}
