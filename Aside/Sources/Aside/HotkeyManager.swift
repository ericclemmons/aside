import Foundation
import Carbon
import AppKit
import AsideCore

/// Monitors the global Right Option (⌥) key via a CGEvent tap.
///
/// Fires `onKeyDown` on press, `onKeyUp` on solo release.
/// If any other key is pressed while Option is held (chord, e.g. Raycast ⌥+Space),
/// the press is suppressed and `onCancel` fires instead.
@MainActor
class HotkeyManager {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    var onCancel: (() -> Void)?

    // Unused by AppDelegate (it always passes .holdToTalk), kept for SetupState API compat.
    var mode: HotkeyMode = .holdToTalk

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthCheckTimer: Timer?

    private enum KeyState {
        case idle           // Right Option is not held
        case down           // Right Option held solo — recording active
        case chord          // Another key pressed while Option held — suppress
    }
    private var keyState: KeyState = .idle

    private let rightOptionKeyCode: Int64 = 61

    private(set) var isAccessibilityGranted = false
    var isRunning: Bool { eventTap != nil }

    func resetToggle() {
        keyState = .idle
    }

    static func checkAccessibilityPermission() -> Bool {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        )
    }

    @discardableResult
    func start() -> Bool {
        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                let suppress = manager.handleEvent(type: type, event: event)
                return suppress ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("[HotkeyManager] Failed to create event tap. Grant Accessibility permission.")
            isAccessibilityGranted = false
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isAccessibilityGranted = true
        NSLog("[HotkeyManager] Event tap created successfully")
        startHealthCheck()
        return true
    }

    func stop() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    /// Periodically verifies the event tap is still alive. macOS can silently
    /// invalidate the mach port (e.g. after sleep/wake or prolonged inactivity),
    /// and the tapDisabledByTimeout callback won't fire if the port itself is dead.
    private func startHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndRevive()
            }
        }
    }

    private func checkAndRevive() {
        guard let tap = eventTap else { return }

        if !CFMachPortIsValid(tap) {
            NSLog("[HotkeyManager] Mach port invalid — recreating event tap")
            stop()
            start()
            return
        }

        if !CGEvent.tapIsEnabled(tap: tap) {
            NSLog("[HotkeyManager] Event tap disabled (health check) — re-enabling")
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    /// Returns `true` if the event should be suppressed (not passed to the system).
    @discardableResult
    private func handleEvent(type: CGEventType, event: CGEvent) -> Bool {
        // macOS disables event taps if callback is slow — re-enable immediately
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            NSLog("[HotkeyManager] Event tap was disabled, re-enabling")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .keyDown {
            switch keyState {
            case .idle:
                if keyCode == 53 {
                    // Escape during persistent recording (Option already released)
                    Task { @MainActor in self.onCancel?() }
                }
            case .down:
                if keyCode == 53 {
                    // Escape: cancel recording
                    keyState = .idle
                    Task { @MainActor in self.onCancel?() }
                } else {
                    // Chord (e.g. ⌥+Space for Raycast): suppress and cancel
                    keyState = .chord
                    Task { @MainActor in self.onCancel?() }
                }
            case .chord:
                break  // Already suppressed
            }
            return false
        }

        guard type == .flagsChanged, keyCode == rightOptionKeyCode else { return false }

        let optionIsDown = event.flags.contains(.maskAlternate)
        NSLog("[HotkeyManager] Right Option %@ (state: %@)", optionIsDown ? "down" : "up", "\(keyState)")

        switch keyState {
        case .idle where optionIsDown:
            keyState = .down
            Task { @MainActor in self.onKeyDown?() }
            return true  // Suppress Right Option down

        case .down where !optionIsDown:
            keyState = .idle
            Task { @MainActor in self.onKeyUp?() }
            return true  // Suppress Right Option up

        case .chord where !optionIsDown:
            // Suppressed press released — back to idle, no callback
            keyState = .idle
            return true  // Suppress Right Option up after chord

        default:
            return false
        }
    }
}
