import SwiftUI
import AppKit
import AVFoundation
import Speech
import Combine
import AsideCore

// MARK: - Setup Step

enum SetupStep: Int, CaseIterable {
    case welcome
    case screenRecording
    case microphone
    case speechRecognition
    case accessibility
    case openCodeSetup
    case tryHoldToType
    case tryTapToDispatch
}

// MARK: - Setup State

@MainActor
class SetupState: ObservableObject {
    @Published var currentStep: SetupStep = .welcome
    @Published var micGranted = false
    @Published var speechGranted = false
    @Published var screenRecordingGranted = false
    @Published var accessibilityGranted = false
    @Published var tryInput: String = ""
    @Published var tryDispatchTested: Bool = false
    var openCodeConfig: OpenCodeConfig?

    @Published var contentHeight: CGFloat = 0
    var onComplete: (() -> Void)?
    /// Called when setup needs the hotkey to be active for "try" steps.
    /// Parameter is the mode to use for the step.
    var onSetupHotkey: ((HotkeyMode) -> Void)?

    /// Call when a tap-to-dispatch cycle completes (or is cancelled) during setup.
    func markDispatchTested() {
        tryDispatchTested = true
        // Auto-close setup when the user completes a dispatch on the final step
        if currentStep == .tryTapToDispatch {
            onComplete?()
        }
    }

    func checkPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        screenRecordingGranted = Self.canScreenRecordingWork()
        accessibilityGranted = Self.canAccessibilityWork()
        NSLog("[Setup] Permissions — mic: \(micGranted), speech: \(speechGranted), screenRecording: \(screenRecordingGranted), accessibility: \(accessibilityGranted)")
    }

    /// Clear a stale TCC entry so the user sees a clean slate in System Preferences.
    /// Requires the app to be codesigned with a stable --identifier matching the bundle ID.
    static func resetTCCEntry(_ service: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        proc.arguments = ["reset", service, Bundle.main.bundleIdentifier ?? "com.ericclemmons.aside.app"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
    }

    /// Test screen recording by checking if we can read window names from other processes.
    /// Without permission, kCGWindowName is absent for other apps' windows.
    /// Unlike CGPreflightScreenCaptureAccess(), this reflects permission changes immediately.
    static func canScreenRecordingWork() -> Bool {
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

    /// Test accessibility by attempting to create a CGEvent tap.
    /// Unlike AXIsProcessTrustedWithOptions(), this reflects permission changes immediately.
    static func canAccessibilityWork() -> Bool {
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        ) else { return false }
        CFMachPortInvalidate(tap)
        return true
    }

    func advance() {
        NSLog("[Setup] advance() called from step: \(currentStep)")
        guard let currentIndex = SetupStep.allCases.firstIndex(of: currentStep) else { return }
        let nextIndex = SetupStep.allCases.index(after: currentIndex)

        // Past the last step — setup complete
        guard nextIndex < SetupStep.allCases.endIndex else {
            NSLog("[Setup] advance() → all steps complete")
            onComplete?()
            return
        }

        let next = SetupStep.allCases[nextIndex]

        // Skip permission steps that are already granted
        switch next {
        case .microphone where micGranted:
            NSLog("[Setup] advance() → skipping microphone (already granted)")
            currentStep = next
            advance()
            return
        case .speechRecognition where speechGranted:
            NSLog("[Setup] advance() → skipping speechRecognition (already granted)")
            currentStep = next
            advance()
            return
        case .screenRecording where screenRecordingGranted:
            NSLog("[Setup] advance() → skipping screenRecording (screenRecordingGranted=true)")
            currentStep = next
            advance()
            return
        case .accessibility where accessibilityGranted:
            NSLog("[Setup] advance() → skipping accessibility (already granted)")
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

        NSLog("[Setup] advance() → moving to step: \(next)")
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
        case .screenRecording:
            let granted = Self.canScreenRecordingWork()
            screenRecordingGranted = granted
            if granted {
                advance()
            } else {
                // Request adds Aside to the Screen Recording list in System Preferences
                CGRequestScreenCaptureAccess()
                // Also open Settings so the user can toggle it on
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                startPermissionPolling()
            }
        case .accessibility:
            let trusted = Self.canAccessibilityWork()
            accessibilityGranted = trusted
            if trusted {
                advance()
            } else {
                Self.resetTCCEntry("Accessibility")
                // Prompt the system dialog to add Aside to the Accessibility list
                AXIsProcessTrustedWithOptions(
                    [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                )
                startPermissionPolling()
            }
        case .tryHoldToType:
            // "Skip" button
            advance()
        case .openCodeSetup:
            advance()
        case .tryTapToDispatch:
            // Final step — close setup and start using
            onComplete?()
        }
    }

    private var permissionTimer: Timer?
    @Published var isPollingPermission = false

    private func startPermissionPolling() {
        NSLog("[Setup] startPermissionPolling() for step: \(currentStep)")
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
                case .screenRecording:
                    granted = Self.canScreenRecordingWork()
                    self.screenRecordingGranted = granted
                case .accessibility:
                    granted = Self.canAccessibilityWork()
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

    // MARK: - OpenCode polling

    private var openCodeTimer: Timer?

    func startOpenCodePolling() {
        openCodeTimer?.invalidate()
        isPollingPermission = true
        openCodeTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.currentStep == .openCodeSetup else {
                    self?.openCodeTimer?.invalidate()
                    self?.openCodeTimer = nil
                    return
                }
                self.openCodeConfig?.discover()
                if self.openCodeConfig?.isConnected == true {
                    self.openCodeTimer?.invalidate()
                    self.openCodeTimer = nil
                    self.isPollingPermission = false
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

// MARK: - Preference key for content height

private struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Lightweight mic level monitor (no transcription)

@MainActor
class MicLevelMonitor: ObservableObject {
    @Published var audioLevel: Float = 0
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?

    func start() {
        guard recorder == nil else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".caf")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
        ]
        guard let rec = try? AVAudioRecorder(url: url, settings: settings) else { return }
        rec.isMeteringEnabled = true   // must be set before record()
        guard rec.record() else { return }
        recorder = rec

        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let rec = self.recorder else { return }
                rec.updateMeters()
                // averagePower: -160 dB silence → 0 dB max. Map -40..0 dB → 0..1.
                let db = rec.averagePower(forChannel: 0)
                self.audioLevel = Float(max(0, min(1, (Double(db) + 40) / 40)))
            }
        }
    }

    func stop() {
        meterTimer?.invalidate(); meterTimer = nil
        recorder?.stop()
        if let url = recorder?.url { try? FileManager.default.removeItem(at: url) }
        recorder = nil
        audioLevel = 0
    }
}

// WaveformBanner extracted to Views/WaveformBanner.swift
// SetupView replaced by Views/SetupView.swift (store-driven)

// MARK: - Legacy Setup View (kept for reference, renamed to avoid conflict)

struct LegacySetupView: View {
    @ObservedObject var state: SetupState
    @FocusState private var tryInputFocused: Bool
    @State private var copiedKey: String? = nil
    @StateObject private var micMonitor = MicLevelMonitor()

    private var waveformSteps: Set<SetupStep> { [.microphone, .speechRecognition] }

    private func updateMonitor() {
        if waveformSteps.contains(state.currentStep) && state.micGranted {
            micMonitor.start()
        } else {
            micMonitor.stop()
        }
    }

    var body: some View {
        Group {
            switch state.currentStep {
            case .welcome:            welcomeCard
            case .microphone:         microphoneCard
            case .speechRecognition:  speechRecognitionCard
            case .screenRecording:    screenRecordingCard
            case .accessibility:      accessibilityCard
            case .openCodeSetup:      openCodeCard
            case .tryHoldToType:      holdToTypeCard
            case .tryTapToDispatch:   tapToDispatchCard
            }
        }
        .frame(width: 420)
        .background(GeometryReader { geo in
            Color.clear.preference(key: HeightPreferenceKey.self, value: geo.size.height)
        })
        .onPreferenceChange(HeightPreferenceKey.self) { h in
            if h > 0 { state.contentHeight = h }
        }
        .animation(.easeInOut(duration: 0.3), value: state.currentStep)
        .onAppear { updateMonitor() }
        .onDisappear { micMonitor.stop() }
        .onChange(of: state.currentStep) { updateMonitor() }
        .onChange(of: state.micGranted)  { updateMonitor() }
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
    }

    // MARK: - Welcome card

    private var welcomeCard: some View {
        VStack(spacing: 0) {
            WaveformBanner(audioLevel: 0, liveMode: false)
                .frame(height: 96)
            Spacer(minLength: 28)
            Text("Welcome to Aside")
                .font(.system(size: 20, weight: .semibold))
                .padding(.bottom, 12)
            Text("Aside is a voice assistant that lives in your menu bar. Hold the Right Option key to dictate text, or tap it to send voice prompts to your coding agent.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)
            Button(action: { state.advance() }) {
                Text("Get Started")
                    .font(.system(size: 13, weight: .medium))
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            progressDots
                .padding(.top, 20)
                .padding(.bottom, 24)
        }
    }

    // MARK: - Microphone card

    private var microphoneCard: some View {
        VStack(spacing: 0) {
            WaveformBanner(audioLevel: micMonitor.audioLevel, liveMode: true)
                .frame(height: 96)
            Spacer(minLength: 28)
            Text("Record Your Voice")
                .font(.system(size: 20, weight: .semibold))
                .padding(.bottom, 12)
            Text("Aside needs microphone access to hear your voice. All audio stays on your Mac — nothing leaves your device.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)
            if state.micGranted {
                permissionGrantedBadge
                    .padding(.bottom, 12)
            }
            permissionPollingIndicator
            Button(action: { state.requestCurrentPermission() }) {
                Text(microphoneButtonLabel)
                    .font(.system(size: 13, weight: .medium))
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            progressDots
                .padding(.top, 20)
                .padding(.bottom, 24)
        }
    }

    private var microphoneButtonLabel: String {
        if state.micGranted { return "Continue" }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .denied { return "Open Microphone Settings" }
        return "Allow Microphone"
    }

    // MARK: - Speech Recognition card

    private var speechRecognitionCard: some View {
        VStack(spacing: 0) {
            WaveformBanner(audioLevel: micMonitor.audioLevel, liveMode: true)
                .frame(height: 96)
            Spacer(minLength: 28)
            Text("Local Transcription")
                .font(.system(size: 20, weight: .semibold))
                .padding(.bottom, 12)
            Text("Apple's speech recognition converts your voice to text in real-time. This powers the live transcription you see while speaking.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)
            if state.speechGranted {
                permissionGrantedBadge
                    .padding(.bottom, 12)
            }
            permissionPollingIndicator
            Button(action: { state.requestCurrentPermission() }) {
                Text(speechRecognitionButtonLabel)
                    .font(.system(size: 13, weight: .medium))
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            progressDots
                .padding(.top, 20)
                .padding(.bottom, 24)
        }
    }

    private var speechRecognitionButtonLabel: String {
        if state.speechGranted { return "Continue" }
        if SFSpeechRecognizer.authorizationStatus() == .denied { return "Open Speech Settings" }
        return "Allow Transcription"
    }

    // MARK: - Screen Recording card

    private var screenRecordingCard: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
                .frame(height: 60)
                .padding(.bottom, 24)
            Text("Screenshots")
                .font(.system(size: 20, weight: .semibold))
                .padding(.bottom, 12)
            Text("Aside can capture screenshots while you speak, attaching them to your prompt.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)
            if state.screenRecordingGranted {
                permissionGrantedBadge
                    .padding(.bottom, 12)
            }
            permissionPollingIndicator
            Button(action: { state.requestCurrentPermission() }) {
                Text(state.screenRecordingGranted ? "Continue" : "Allow Screen Recording")
                    .font(.system(size: 13, weight: .medium))
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            progressDots
                .padding(.top, 20)
                .padding(.bottom, 24)
        }
    }

    // MARK: - Accessibility card

    private var accessibilityCard: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)
            Image(systemName: "keyboard.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
                .frame(height: 60)
                .padding(.bottom, 24)
            Text("Push-to-Talk Hotkey")
                .font(.system(size: 20, weight: .semibold))
                .padding(.bottom, 12)
            Text("Aside uses the Right Option key as a system-wide hotkey. macOS requires Accessibility access to detect keystrokes outside the app.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)
            if state.accessibilityGranted {
                permissionGrantedBadge
                    .padding(.bottom, 12)
            }
            if state.isPollingPermission && !state.accessibilityGranted {
                VStack(spacing: 4) {
                    Text("If Aside is already listed, remove it")
                    Text("with the \u{2212} button first, then try again.")
                }
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
            }
            permissionPollingIndicator
            Button(action: { state.requestCurrentPermission() }) {
                Text(state.accessibilityGranted ? "Continue" : "Open Accessibility Settings")
                    .font(.system(size: 13, weight: .medium))
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            progressDots
                .padding(.top, 20)
                .padding(.bottom, 24)
        }
    }

    // MARK: - OpenCode card

    private var openCodeCard: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)
            if let url = Bundle.main.url(forResource: "opencode.wordmark", withExtension: "svg"),
               let img = NSImage(contentsOf: url) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 60)
                    .padding(.bottom, 36)
            } else {
                Text("OpenCode Desktop")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(height: 60)
                    .padding(.bottom, 36)
            }

            Text("Aside requires OpenCode Desktop to sync sessions. You can still use the OpenCode CLI independently.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)

            if let server = state.openCodeConfig?.server {
                Label {
                    Text("Running on ") .font(.system(size: 13)) +
                    Text("localhost:\(String(server.port))") .font(.system(size: 13, design: .monospaced))
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .foregroundStyle(.green)
                .padding(.bottom, 12)
            } else {
                Button(action: {
                    let appURL = URL(fileURLWithPath: "/Applications/OpenCode.app")
                    if FileManager.default.fileExists(atPath: appURL.path) {
                        NSWorkspace.shared.open(appURL)
                    } else {
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                        process.arguments = ["-a", "OpenCode"]
                        try? process.run()
                    }
                }) {
                    Text("Open OpenCode Desktop")
                        .font(.system(size: 13, weight: .medium))
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 12)

                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for server...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            progressDots
                .padding(.top, 16)
                .padding(.bottom, 24)
        }
        .onAppear {
            state.startOpenCodePolling()
        }
    }

    // MARK: - Hold-to-Type card

    private var holdToTypeCard: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)
            keyboardIllustration
                .padding(.bottom, 24)
            Text("Hold-to-Type")
                .font(.system(size: 20, weight: .semibold))
                .padding(.bottom, 12)
            Text("Hold Right ⌥ and say something. When you release, your words will be typed into the text field below.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)
            TextField("Hold Right ⌥ and speak...", text: $state.tryInput)
                .textFieldStyle(.roundedBorder)
                .focused($tryInputFocused)
                .frame(maxWidth: 300)
                .onAppear { tryInputFocused = true }
                .onChange(of: state.tryInput) {
                    if !state.tryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            if state.currentStep == .tryHoldToType {
                                state.advance()
                            }
                        }
                    }
                }
                .padding(.bottom, 20)
            progressDots
                .padding(.top, 20)
                .padding(.bottom, 24)
        }
    }

    // MARK: - Tap-to-Dispatch card

    private var tapToDispatchCard: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)
            keyboardIllustration
                .padding(.bottom, 24)
            Text("Tap-to-Agent")
                .font(.system(size: 20, weight: .semibold))
                .padding(.bottom, 12)
            numberedSteps
                .padding(.bottom, 20)
            Button(action: { state.requestCurrentPermission() }) {
                Text("Finish Setup")
                    .font(.system(size: 13, weight: .medium))
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            progressDots
                .padding(.top, 20)
                .padding(.bottom, 24)
        }
    }

    // MARK: - Shared subviews

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(SetupStep.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step.rawValue <= state.currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
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

    @ViewBuilder
    private var permissionPollingIndicator: some View {
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
    }

    // MARK: - Numbered steps (Tap-to-Agent step)

    private var numberedSteps: some View {
        VStack(alignment: .leading, spacing: 6) {
            stepRow(number: 1, text: "Tap Right ⌥ to start recording")
            stepRow(number: 2, text: "Speak your prompt")
            stepRow(number: 3, text: "Tap Right ⌥ again to stop")
            stepRow(number: 4, text: "Press Enter to send")
        }
        .frame(maxWidth: 280, alignment: .leading)
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            numberBadge(number)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Keyboard illustration

    private var keyboardIllustration: some View {
        HStack(spacing: 3) {
            keyCap("", width: 160, highlight: false)
            keyCapSymbol("⌘", sublabel: "command", width: 50, highlight: false)
            keyCapSymbol("⌥", sublabel: "option",  width: 50, highlight: true)
            keyCapSymbol("←", sublabel: nil,        width: 36, highlight: false)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: 42)
    }

    private func keyCap(_ label: String, width: CGFloat, highlight: Bool) -> some View {
        Text(label)
            .font(.system(size: 11, weight: highlight ? .semibold : .regular))
            .foregroundStyle(highlight ? Color.white : Color.black.opacity(0.55))
            .frame(width: width, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(highlight ? Color.accentColor : Color.white)
                    .shadow(color: .black.opacity(0.12), radius: 0.5, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(highlight ? Color.accentColor : Color.black.opacity(0.12), lineWidth: 0.5)
            )
    }

    private func keyCapSymbol(_ symbol: String, sublabel: String?, width: CGFloat, highlight: Bool) -> some View {
        let fg = highlight ? Color.white : Color.black.opacity(0.6)
        return VStack(alignment: .leading, spacing: 1) {
            Text(symbol)
                .font(.system(size: sublabel != nil ? 11 : 14, weight: highlight ? .semibold : .regular))
                .foregroundStyle(fg)
            if let sublabel {
                Text(sublabel)
                    .font(.system(size: 7.5))
                    .foregroundStyle(fg.opacity(0.7))
            }
        }
        .padding(.leading, 6)
        .frame(width: width, height: 36, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(highlight ? Color.accentColor : Color.white)
                .shadow(color: .black.opacity(0.12), radius: 0.5, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(highlight ? Color.accentColor : Color.black.opacity(0.12), lineWidth: 0.5)
        )
    }

    // MARK: - OpenCode helpers

    /// Clipboard button that briefly shows a checkmark on tap.
    private func clipboardButton(_ text: String, key: String, size: CGFloat) -> some View {
        Button(action: { copyToClipboard(text, key: key) }) {
            Image(systemName: copiedKey == key ? "checkmark" : "doc.on.doc")
                .font(.system(size: size))
                .foregroundStyle(copiedKey == key ? Color.green : Color.secondary)
        }
        .buttonStyle(.plain)
        .help("Copy to clipboard")
    }

    private func copyToClipboard(_ text: String, key: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation { copiedKey = key }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { if copiedKey == key { copiedKey = nil } }
        }
    }

    private func numberBadge(_ n: Int) -> some View {
        Text("\(n)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(Color.accentColor))
    }

    // MARK: - Image loading + shadow trimming

    private static var imageCache: [String: NSImage] = [:]

    private func loadResourceImage(_ name: String) -> NSImage? {
        if let cached = Self.imageCache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let raw = NSImage(contentsOf: url) else { return nil }
        let trimmed = trimTransparentBorder(raw)
        Self.imageCache[name] = trimmed
        return trimmed
    }

    /// Strips the transparent macOS drop-shadow border from a PNG screenshot
    /// so it renders edge-to-edge inside the card.
    private func trimTransparentBorder(_ image: NSImage) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return image }

        // Render into RGBA buffer with top-left origin (flip CTM)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space, bitmapInfo: info)
        else { return image }
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        func a(_ x: Int, _ y: Int) -> UInt8 { px[(y * w + x) * 4 + 3] }

        var x0 = 0, x1 = w - 1, y0 = 0, y1 = h - 1
        outer: for y in 0..<h { for x in 0..<w { if a(x,y) > 10 { y0 = y; break outer } } }
        outer: for y in stride(from: h-1, through: 0, by: -1) { for x in 0..<w { if a(x,y) > 10 { y1 = y; break outer } } }
        outer: for x in 0..<w { for y in y0...y1 { if a(x,y) > 10 { x0 = x; break outer } } }
        outer: for x in stride(from: w-1, through: 0, by: -1) { for y in y0...y1 { if a(x,y) > 10 { x1 = x; break outer } } }

        guard x0 < x1, y0 < y1 else { return image }

        let nw = x1 - x0 + 1, nh = y1 - y0 + 1
        var out = [UInt8](repeating: 0, count: nw * nh * 4)
        for y in 0..<nh {
            let src = (y0 + y) * w * 4 + x0 * 4
            let dst = y * nw * 4
            out.replaceSubrange(dst..<dst + nw * 4, with: px[src..<src + nw * 4])
        }
        guard let dp = CGDataProvider(data: Data(out) as CFData),
              let outCG = CGImage(width: nw, height: nh, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: nw * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: info),
                                  provider: dp, decode: nil, shouldInterpolate: true,
                                  intent: .defaultIntent)
        else { return image }

        let scale = image.size.width / CGFloat(w)
        return NSImage(cgImage: outCG, size: CGSize(width: CGFloat(nw) * scale, height: CGFloat(nh) * scale))
    }
}

// MARK: - Setup Window

class SetupWindowController {
    private var windowController: NSWindowController?
    private(set) var state: SetupState?
    private var heightSink: AnyCancellable?

    @MainActor
    func show(openCodeConfig: OpenCodeConfig, onSetupHotkey: ((HotkeyMode) -> Void)? = nil, onComplete: @escaping () -> Void) {
        let state = SetupState()
        state.openCodeConfig = openCodeConfig
        self.state = state
        state.checkPermissions()

        // If all permissions already granted, skip setup entirely
        if state.micGranted && state.speechGranted
            && state.screenRecordingGranted && state.accessibilityGranted {
            onComplete()
            return
        }

        state.onComplete = { [weak self] in
            self?.close()
            onComplete()
        }

        state.onSetupHotkey = onSetupHotkey

        let setupView = LegacySetupView(state: state)
            .environment(\.colorScheme, .dark)
            .preferredColorScheme(.dark)
        let hostingController = NSHostingController(rootView: setupView)
        hostingController.view.appearance = NSAppearance(named: .darkAqua)

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentViewController = hostingController
        window.contentView?.appearance = NSAppearance(named: .darkAqua)
        window.setContentSize(NSSize(width: 420, height: 340))
        window.title = "Aside"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller

        // Animate window height whenever SwiftUI content size changes
        heightSink = state.$contentHeight
            .filter { $0 > 0 }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak controller] height in
                guard let window = controller?.window else { return }
                let titleH = window.frame.height - window.contentRect(forFrameRect: window.frame).height
                let newContentH = height
                var frame = window.frame
                let delta = newContentH - (window.frame.height - titleH)
                frame.origin.y -= delta   // keep top edge fixed
                frame.size.height += delta
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(frame, display: true)
                }
            }

        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView?.appearance = NSAppearance(named: .darkAqua)
    }

    func close() {
        heightSink = nil
        windowController?.window?.close()
        windowController = nil
        state = nil
    }
}
