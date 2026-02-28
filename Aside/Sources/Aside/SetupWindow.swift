import SwiftUI
import AppKit
import AVFoundation
import Speech

// MARK: - Setup Step

enum SetupStep: Int, CaseIterable {
    case welcome
    case microphone
    case speechRecognition
    case accessibility
    case tryHoldToType
    case tryTapToDispatch
    case done

    var title: String {
        switch self {
        case .welcome: return "Welcome to Aside"
        case .microphone: return "Record Your Voice"
        case .speechRecognition: return "Local Transcription"
        case .accessibility: return "Push-to-Talk Hotkey"
        case .tryHoldToType: return "Try Hold-to-Type"
        case .tryTapToDispatch: return "Try Tap-to-Dispatch"
        case .done: return "You're All Set!"
        }
    }

    var explanation: String {
        switch self {
        case .welcome:
            return "Aside is a voice assistant that lives in your menu bar. Hold the Right Option key to dictate text, or tap it to send voice prompts to your coding agent."
        case .microphone:
            return "Aside needs microphone access to hear your voice. All audio stays on your Mac — nothing leaves your device."
        case .speechRecognition:
            return "Apple's speech recognition converts your voice to text in real-time. This powers the live transcription you see while speaking."
        case .accessibility:
            return "Aside uses the Right Option key as a system-wide hotkey. macOS requires Accessibility access to detect keystrokes outside the app."
        case .tryHoldToType:
            return "Hold Right ⌥ and say something. When you release, your words will be typed into the text field below."
        case .tryTapToDispatch:
            return "Tap Right ⌥ to start recording, speak, then tap again. You'll see a picker to choose where to send your prompt. Press Esc to cancel."
        case .done:
            return "Look for the waveform icon in your menu bar.\n\nHold Right ⌥ → dictate into any text field\nTap Right ⌥ → voice prompt to Claude or OpenCode"
        }
    }

    var icon: String {
        switch self {
        case .welcome: return "waveform.circle.fill"
        case .microphone: return "mic.fill"
        case .speechRecognition: return "text.bubble.fill"
        case .accessibility: return "keyboard.fill"
        case .tryHoldToType: return "hand.point.up.fill"
        case .tryTapToDispatch: return "paperplane.fill"
        case .done: return "checkmark.circle.fill"
        }
    }

    var buttonLabel: String {
        switch self {
        case .welcome: return "Get Started"
        case .microphone: return "Allow Microphone"
        case .speechRecognition: return "Allow Transcription"
        case .accessibility: return "Open Accessibility Settings"
        case .tryHoldToType: return "Continue"
        case .tryTapToDispatch: return "Continue"
        case .done: return "Start Using Aside"
        }
    }

    var isPermissionStep: Bool {
        switch self {
        case .microphone, .speechRecognition, .accessibility: return true
        default: return false
        }
    }

    var isTryStep: Bool {
        switch self {
        case .tryHoldToType, .tryTapToDispatch: return true
        default: return false
        }
    }
}

// MARK: - Setup State

@MainActor
class SetupState: ObservableObject {
    @Published var currentStep: SetupStep = .welcome
    @Published var micGranted = false
    @Published var speechGranted = false
    @Published var accessibilityGranted = false
    @Published var tryInput: String = ""
    @Published var tryDispatchTested: Bool = false

    var onComplete: (() -> Void)?
    /// Called when setup needs the hotkey to be active for "try" steps.
    /// Parameter is the mode to use for the step.
    var onSetupHotkey: ((HotkeyMode) -> Void)?

    /// Call when a tap-to-dispatch cycle completes (or is cancelled) during setup.
    func markDispatchTested() {
        tryDispatchTested = true
    }

    func checkPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        accessibilityGranted = AXIsProcessTrustedWithOptions(nil)
        print("[Setup] Permissions — mic: \(micGranted), speech: \(speechGranted), accessibility: \(accessibilityGranted)")

        // Clear stale TCC entries from previous builds so the fresh binary
        // can re-request permissions cleanly.
        if !micGranted { resetTCC("Microphone") }
        if !speechGranted { resetTCC("SpeechRecognition") }
        if !accessibilityGranted { resetTCC("Accessibility") }
    }

    private func resetTCC(_ service: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, "com.aside.app"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        print("[Setup] Reset TCC for \(service)")
    }

    func advance() {
        guard let currentIndex = SetupStep.allCases.firstIndex(of: currentStep) else { return }
        let nextIndex = SetupStep.allCases.index(after: currentIndex)
        guard nextIndex < SetupStep.allCases.endIndex else { return }

        let next = SetupStep.allCases[nextIndex]

        // Skip permission steps that are already granted
        switch next {
        case .microphone where micGranted:
            currentStep = next
            advance()
            return
        case .speechRecognition where speechGranted:
            currentStep = next
            advance()
            return
        case .accessibility where accessibilityGranted:
            currentStep = next
            advance()
            return
        case .tryHoldToType:
            onSetupHotkey?(.holdToTalk)
        case .tryTapToDispatch:
            onSetupHotkey?(.toggle)
        default:
            break
        }

        currentStep = next

        // Bring setup window back to front after permission dialogs
        NSApp.activate(ignoringOtherApps: true)
    }

    func requestCurrentPermission() {
        switch currentStep {
        case .welcome:
            advance()
        case .microphone:
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            if micStatus == .denied || micStatus == .restricted {
                // Already denied — open System Settings and poll
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                startPermissionPolling()
            } else {
                Task {
                    let granted = await AVCaptureDevice.requestAccess(for: .audio)
                    NSApp.activate(ignoringOtherApps: true)
                    micGranted = granted
                    if granted { advance() }
                }
            }
        case .speechRecognition:
            let speechStatus = SFSpeechRecognizer.authorizationStatus()
            if speechStatus == .denied || speechStatus == .restricted {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!)
                startPermissionPolling()
            } else {
                SFSpeechRecognizer.requestAuthorization { [weak self] status in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        NSApp.activate(ignoringOtherApps: true)
                        self.speechGranted = status == .authorized
                        if status == .authorized { self.advance() }
                    }
                }
            }
        case .accessibility:
            let trusted = AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            )
            accessibilityGranted = trusted
            if trusted {
                advance()
            } else {
                startPermissionPolling()
            }
        case .tryHoldToType, .tryTapToDispatch:
            // "Skip" button
            advance()
        case .done:
            onComplete?()
        }
    }

    private var permissionTimer: Timer?
    @Published var isPollingPermission = false

    private func startPermissionPolling() {
        isPollingPermission = true
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                var granted = false
                switch self.currentStep {
                case .microphone:
                    granted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                    self.micGranted = granted
                case .speechRecognition:
                    granted = SFSpeechRecognizer.authorizationStatus() == .authorized
                    self.speechGranted = granted
                case .accessibility:
                    granted = AXIsProcessTrustedWithOptions(nil)
                    self.accessibilityGranted = granted
                default:
                    break
                }
                if granted {
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                    self.isPollingPermission = false
                    NSApp.activate(ignoringOtherApps: true)
                    self.advance()
                }
            }
        }
    }
}

// MARK: - Collection safe subscript

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Setup View

struct SetupView: View {
    @ObservedObject var state: SetupState
    @FocusState private var tryInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 6) {
                ForEach(SetupStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step.rawValue <= state.currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 20)

            Spacer()

            // Icon
            Image(systemName: state.currentStep.icon)
                .font(.system(size: 48))
                .foregroundStyle(iconColor)
                .frame(height: 60)
                .padding(.bottom, 16)

            // Title
            Text(state.currentStep.title)
                .font(.system(size: 20, weight: .semibold))
                .padding(.bottom, 8)

            // Explanation
            Text(state.currentStep.explanation)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, state.currentStep.isTryStep ? 12 : 24)

            // Try-it input field for hold-to-type step
            if state.currentStep == .tryHoldToType {
                TextField("Hold Right ⌥ and speak...", text: $state.tryInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($tryInputFocused)
                    .frame(maxWidth: 300)
                    .onAppear { tryInputFocused = true }
                    .onSubmit { if !state.tryInput.isEmpty { state.advance() } }
                    .padding(.bottom, 16)
            }

            // Permission granted badge
            if isCurrentStepGranted {
                permissionGrantedBadge
                    .padding(.bottom, 12)
            }

            // Waiting for permission toggle in System Settings
            if state.isPollingPermission {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for permission...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 12)
            }

            // Action button
            Button(action: {
                state.requestCurrentPermission()
            }) {
                Text(buttonLabel)
                    .font(.system(size: 13, weight: .medium))
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(isContinueDisabled)

            Spacer()
        }
        .frame(width: 420, height: state.currentStep.isTryStep ? 380 : 340)
        .animation(.easeInOut(duration: 0.3), value: state.currentStep)
    }

    private var iconColor: Color {
        switch state.currentStep {
        case .done: return .green
        case .tryHoldToType, .tryTapToDispatch: return .orange
        default: return .accentColor
        }
    }

    private var isContinueDisabled: Bool {
        switch state.currentStep {
        case .tryHoldToType: return state.tryInput.isEmpty
        default: return false
        }
    }

    private var isCurrentStepGranted: Bool {
        switch state.currentStep {
        case .microphone: return state.micGranted
        case .speechRecognition: return state.speechGranted
        case .accessibility: return state.accessibilityGranted
        default: return false
        }
    }

    private var buttonLabel: String {
        if isCurrentStepGranted {
            return "Continue"
        }
        if state.isPollingPermission {
            return state.currentStep.buttonLabel
        }
        // Show "Open Settings" if permission was previously denied
        switch state.currentStep {
        case .microphone where AVCaptureDevice.authorizationStatus(for: .audio) == .denied:
            return "Open Microphone Settings"
        case .speechRecognition where SFSpeechRecognizer.authorizationStatus() == .denied:
            return "Open Speech Settings"
        default:
            return state.currentStep.buttonLabel
        }
    }

    private var permissionGrantedBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Permission granted")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
    }
}

// MARK: - Setup Window

class SetupWindowController {
    private var windowController: NSWindowController?
    private(set) var state: SetupState?

    @MainActor
    func show(onSetupHotkey: ((HotkeyMode) -> Void)? = nil, onComplete: @escaping () -> Void) {
        let state = SetupState()
        self.state = state
        state.checkPermissions()

        // If all permissions already granted, skip setup entirely
        if state.micGranted && state.speechGranted && state.accessibilityGranted {
            onComplete()
            return
        }

        state.onComplete = { [weak self] in
            self?.close()
            onComplete()
        }

        state.onSetupHotkey = onSetupHotkey

        let setupView = SetupView(state: state)
        let hostingController = NSHostingController(rootView: setupView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Aside Setup"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        windowController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }

    func close() {
        windowController?.window?.close()
        windowController = nil
        state = nil
    }
}
