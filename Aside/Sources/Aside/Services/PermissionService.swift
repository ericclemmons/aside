import Foundation
import AppKit
import AVFoundation
import Speech
import AsideCore

/// Checks and requests TCC permissions.
@MainActor
final class PermissionService {

    /// Tracks which permissions we've already requested this process lifetime.
    /// If the user clicks Grant again for a permission we already requested,
    /// we reset TCC and relaunch so the OS prompt fires fresh.
    private var requestedThisSession: Set<Permission> = []

    func checkAll() -> PermissionStatus {
        PermissionStatus(
            screenRecording: checkScreenRecording(),
            microphone: checkMicrophone(),
            speechRecognition: checkSpeechRecognition(),
            accessibility: checkAccessibility()
        )
    }

    func request(_ permission: Permission) async -> Bool {
        // Accessibility always prompts via AX API — no caching issue
        if permission == .accessibility {
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }

        // For TCC-based permissions: if we already requested this session
        // and it's still not granted, reset TCC and relaunch for a clean slate.
        if requestedThisSession.contains(permission) {
            relaunch(resettingPermission: permission)
            return false
        }
        requestedThisSession.insert(permission)

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
            return false // unreachable, handled above
        }
    }

    // MARK: - Relaunch

    private func relaunch(resettingPermission permission: Permission) {
        let service: String
        switch permission {
        case .screenRecording: service = "ScreenCapture"
        case .microphone: service = "Microphone"
        case .speechRecognition: service = "SpeechRecognition"
        case .accessibility: return
        }

        // Reset TCC entry so the OS prompt fires on next launch
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", service, "com.ericclemmons.aside.app"]
        try? reset.run()
        reset.waitUntilExit()

        // Relaunch the app
        let appURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
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
