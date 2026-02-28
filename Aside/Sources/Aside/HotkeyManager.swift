import Foundation
import Carbon
import AppKit

/// Monitors the global Right Option (⌥) hotkey via a CGEvent tap.
/// Supports two modes:
/// - **Hold to Talk**: Press and hold Right Option → `onKeyDown`; release → `onKeyUp`
/// - **Toggle**: First press → `onKeyDown`; second press → `onKeyUp`
@MainActor
class HotkeyManager {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    /// The current hotkey mode. Can be changed at runtime.
    var mode: HotkeyMode = .holdToTalk

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyDown = false

    /// Tracks whether a toggle session is active (only used in toggle mode).
    private var isToggleActive = false

    // Right Option key code is 61
    private let rightOptionKeyCode: Int64 = 61

    /// `true` if the event tap was successfully created (i.e. Accessibility permission is granted).
    private(set) var isAccessibilityGranted = false

    /// Returns `true` if the app currently has Accessibility permission.
    static func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        )
    }

    @discardableResult
    func start() -> Bool {
        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handleEvent(type: type, event: event)
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[HotkeyManager] Failed to create event tap. Grant Accessibility permission.")
            isAccessibilityGranted = false
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isAccessibilityGranted = true
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        guard type == .flagsChanged else { return }

        // Check if this is the Right Option key specifically (keycode 61)
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == rightOptionKeyCode else { return }

        let flags = event.flags
        let optionIsDown = flags.contains(.maskAlternate)

        switch mode {
        case .holdToTalk:
            if optionIsDown && !isKeyDown {
                isKeyDown = true
                Task { @MainActor in self.onKeyDown?() }
            } else if !optionIsDown && isKeyDown {
                isKeyDown = false
                Task { @MainActor in self.onKeyUp?() }
            }

        case .toggle:
            // Detect the rising edge: key was not pressed, now it is
            if optionIsDown && !isKeyDown {
                isKeyDown = true
                if !isToggleActive {
                    // First press: start recording
                    isToggleActive = true
                    Task { @MainActor in self.onKeyDown?() }
                } else {
                    // Second press: stop recording
                    isToggleActive = false
                    Task { @MainActor in self.onKeyUp?() }
                }
            } else if !optionIsDown && isKeyDown {
                // Key released — just reset the edge detector, don't fire callbacks
                isKeyDown = false
            }
        }
    }
}
