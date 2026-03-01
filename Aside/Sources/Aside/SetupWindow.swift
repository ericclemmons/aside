import SwiftUI
import AppKit
import AVFoundation
import Speech
import Combine

// MARK: - Setup Step

enum SetupStep: Int, CaseIterable {
    case welcome
    case microphone
    case speechRecognition
    case accessibility
    case tryHoldToType
    case openCodeSetup
    case tryTapToDispatch

    var title: String {
        switch self {
        case .welcome: return "Welcome to Aside"
        case .microphone: return "Record Your Voice"
        case .speechRecognition: return "Local Transcription"
        case .accessibility: return "Push-to-Talk Hotkey"
        case .tryHoldToType: return "Hold-to-Type"
        case .openCodeSetup: return "Setup OpenCode"
        case .tryTapToDispatch: return "Tap-to-Agent"
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
        case .openCodeSetup:
            return "Open OpenCode Desktop, click Status in the top-right, and add the server shown below."
        case .tryTapToDispatch:
            return "" // Uses custom numbered steps view
        }
    }

    var icon: String {
        switch self {
        case .welcome: return "waveform.circle.fill"
        case .microphone: return "mic.fill"
        case .speechRecognition: return "text.bubble.fill"
        case .accessibility: return "keyboard.fill"
        case .tryHoldToType: return "" // Uses custom keyboard view
        case .openCodeSetup: return "server.rack"
        case .tryTapToDispatch: return "" // Uses custom keyboard view
        }
    }

    var usesKeyboardIllustration: Bool {
        switch self {
        case .tryHoldToType, .tryTapToDispatch: return true
        default: return false
        }
    }

    var buttonLabel: String {
        switch self {
        case .welcome: return "Get Started"
        case .microphone: return "Allow Microphone"
        case .speechRecognition: return "Allow Transcription"
        case .accessibility: return "Open Accessibility Settings"
        case .tryHoldToType: return "Hold Right ⌥"
        case .openCodeSetup: return "Open OpenCode Desktop"
        case .tryTapToDispatch: return "Tap Right ⌥"
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
    @Published var openCodeOpened: Bool = false

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

        // Past the last step — setup complete
        guard nextIndex < SetupStep.allCases.endIndex else {
            onComplete?()
            return
        }

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
        case .tryHoldToType:
            // "Skip" button
            advance()
        case .openCodeSetup:
            if openCodeOpened {
                advance()
            } else {
                // Try to open the OpenCode Desktop app
                let opened = NSWorkspace.shared.open(URL(string: "opencode://")!)
                    || NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/OpenCode.app"))
                if !opened {
                    // Fallback: open the web download page
                    NSWorkspace.shared.open(URL(string: "https://opencode.ai")!)
                }
                openCodeOpened = true
            }
        case .tryTapToDispatch:
            // Final step — close setup and start using
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

// MARK: - Preference key for content height

private struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Lightweight mic level monitor (no transcription)

@MainActor
private class MicLevelMonitor: ObservableObject {
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

// MARK: - Waveform banner (welcome / mic / speech steps)

private struct SetupWaveformBanner: View {
    var audioLevel: Float = 0
    /// false = always-on idle animation (welcome screen)
    /// true  = flat at silence, driven by mic (mic/speech screens)
    var liveMode: Bool = false

    @State private var phase: Double = 0
    @State private var smoothedLevel: Double = 0
    @State private var animTimer: Timer?
    // Mirror of audioLevel prop in @State so the timer closure can read live updates.
    // Plain var props on View structs are value-captured at onAppear and never update.
    @State private var currentAudioLevel: Float = 0

    // Filled colour layers — amplitude fraction, frequency, phase speed, initial offset, opacity
    private let colorLayers: [(amp: Double, freq: Double, speed: Double, offset: Double, opacity: Double)] = [
        (0.70, 1.05, 0.60, 0.00,       0.55),
        (0.55, 1.80, 1.00, .pi * 0.65, 0.45),
        (0.80, 0.70, 0.40, .pi * 1.30, 0.35),
        (0.45, 2.50, 1.50, .pi * 0.35, 0.40),
    ]

    // White glow lines — amplitude fraction, frequency, phase speed, initial offset, base opacity
    private let strokeLines: [(amp: Double, freq: Double, speed: Double, offset: Double, opacity: Double)] = [
        (0.60, 1.40, 0.85, .pi * 0.20, 0.7),
        (0.50, 2.10, 1.25, .pi * 1.10, 0.6),
        (0.75, 0.90, 0.55, .pi * 1.80, 0.5),
    ]

    // Purple → indigo → teal → pink
    private let gradient = Gradient(stops: [
        .init(color: Color(red: 0.55, green: 0.10, blue: 1.00), location: 0.00),
        .init(color: Color(red: 0.20, green: 0.35, blue: 1.00), location: 0.33),
        .init(color: Color(red: 0.00, green: 0.75, blue: 0.90), location: 0.66),
        .init(color: Color(red: 0.85, green: 0.15, blue: 0.85), location: 1.00),
    ])

    var body: some View {
        Canvas { context, size in
            let midY  = size.height / 2
            let halfH = midY * 0.88
            let steps = 220

            // liveMode: flat at silence, driven by voice.
            // idle mode: always-on animation, audio gently boosts amplitude.
            let ampScale = liveMode
                ? smoothedLevel                          // 0 = flat, 1 = full
                : 1.0 + smoothedLevel * 0.6             // always visible, audio adds a little extra

            // 1. Blurry colour fills
            for layer in colorLayers {
                var top = [CGPoint](), bot = [CGPoint]()
                for i in 0...steps {
                    let t   = Double(i) / Double(steps)
                    let x   = CGFloat(t) * size.width
                    let n   = (t - 0.5) * 4.8
                    let env = exp(-n * n * 0.52)
                    let dy  = CGFloat(sin(t * .pi * 2 * layer.freq + phase * layer.speed + layer.offset)
                                      * layer.amp * min(env * ampScale, 1.0)) * halfH
                    top.append(CGPoint(x: x, y: midY - dy))
                    bot.append(CGPoint(x: x, y: midY + dy))
                }
                var path = Path()
                path.move(to: top[0])
                top.dropFirst().forEach { path.addLine(to: $0) }
                bot.reversed().forEach  { path.addLine(to: $0) }
                path.closeSubpath()
                var ctx = context
                ctx.opacity = layer.opacity
                ctx.addFilter(.blur(radius: 3))
                ctx.fill(path, with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: 0,          y: midY),
                    endPoint:   CGPoint(x: size.width, y: midY)
                ))
            }

            // 2. Glowing white lines — three passes per line: outer halo, mid-glow, bright core
            for line in strokeLines {
                var path = Path()
                for i in 0...steps {
                    let t   = Double(i) / Double(steps)
                    let x   = CGFloat(t) * size.width
                    let n   = (t - 0.5) * 4.8
                    let env = exp(-n * n * 0.52)
                    let y   = midY - CGFloat(sin(t * .pi * 2 * line.freq + phase * line.speed + line.offset)
                                             * line.amp * min(env * ampScale, 1.0)) * halfH
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else       { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                // Outer halo — wide, very blurry, soft
                var halo = context; halo.opacity = line.opacity * 0.25
                halo.addFilter(.blur(radius: 10))
                halo.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                // Mid glow
                var mid = context; mid.opacity = line.opacity * 0.45
                mid.addFilter(.blur(radius: 4))
                mid.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                // Bright core — thin, minimal blur
                var core = context; core.opacity = line.opacity * 0.6
                core.addFilter(.blur(radius: 0.5))
                core.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .onAppear { startAnimating() }
        .onDisappear { stopAnimating() }
        .onChange(of: audioLevel) { _, new in currentAudioLevel = new }
    }

    private func startAnimating() {
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in
                phase += 0.038
                // Fast attack, slow decay — reacts instantly to voice, fades gracefully
                let target = Double(currentAudioLevel)
                if target > smoothedLevel {
                    smoothedLevel = smoothedLevel * 0.35 + target * 0.65  // ~4 frames to peak
                } else {
                    smoothedLevel = smoothedLevel * 0.90 + target * 0.10  // ~20 frames to decay
                }
            }
        }
    }

    private func stopAnimating() { animTimer?.invalidate(); animTimer = nil }
}

// MARK: - Setup View

private enum OpenCodeTab: String, CaseIterable {
    case desktop = "Desktop"
    case web     = "Web"
    case cli     = "CLI"
}

struct SetupView: View {
    @ObservedObject var state: SetupState
    @FocusState private var tryInputFocused: Bool
    @State private var openCodeTab: OpenCodeTab = .desktop
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
            if state.currentStep == .openCodeSetup {
                openCodeCard
            } else {
                standardLayout
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
    }

    // MARK: - OpenCode card layout (tabbed: Desktop / Web / CLI)

    private var openCodeCard: some View {
        VStack(spacing: 0) {
            // Wordmark — same vertical rhythm as icon steps in standardLayout
            Spacer(minLength: 48)
            if let url = Bundle.module.url(forResource: "opencode.wordmark", withExtension: "svg"),
               let img = NSImage(contentsOf: url) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 38)
                    .padding(.bottom, 24)
            } else {
                Text(state.currentStep.title)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(height: 60)
                    .padding(.bottom, 24)
            }

            // Tab picker
            Picker("", selection: $openCodeTab) {
                ForEach(OpenCodeTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)

            // Tab content — direct switch so @ViewBuilder images get proper width proposals
            switch openCodeTab {
            case .desktop: desktopTabContent
            case .web:     webTabContent
            case .cli:     cliTabContent
            }

            openCodeCTAButton
                .padding(.top, 16)

            progressDots
                .padding(.top, 16)
                .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var desktopTabContent: some View {
        // Steps 1 + 2
        VStack(alignment: .leading, spacing: 8) {
            openButtonStepRow(number: 1, label: "OpenCode Desktop") {
                let _ = NSWorkspace.shared.open(URL(string: "opencode://")!)
                    || NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/OpenCode.app"))
                state.openCodeOpened = true
            }
            stepRow(number: 2, text: "Click Status in the top-right")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)

        VStack(alignment: .leading, spacing: 8) {
            addServerStepRow(number: 3, key: "serverURL", showExternalLink: false)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var webTabContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            openButtonStepRow(number: 1, label: "http://localhost:4096") {
                NSWorkspace.shared.open(URL(string: "http://localhost:4096")!)
            }
            stepRow(number: 2, text: "Click Status in the top-right")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)

        VStack(alignment: .leading, spacing: 8) {
            addServerStepRow(number: 3, key: "serverURLWeb", showExternalLink: false)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var cliTabContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To share sessions with Aside, launch OpenCode with:")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                Text("opencode --attach localhost:4096")
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                clipboardButton("opencode --attach localhost:4096", key: "cliCmd", size: 12)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - OpenCode helpers

    /// Full-bleed image — GeometryReader guarantees 100% container width.
    /// Shadow trimming (trimTransparentBorder) ensures content starts at pixel 0.
    @ViewBuilder
    private func fullBleedImage(_ name: String) -> some View {
        if let img = loadResourceImage(name) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(img.size.width / max(img.size.height, 1), contentMode: .fit)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
    }

    /// "Open [label ↗]" step row — label is a tappable link with external icon.
    private func openButtonStepRow(number: Int, label: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            numberBadge(number)
            HStack(spacing: 4) {
                Text("Open").foregroundStyle(.secondary)
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(label)
                        Image(systemName: "arrow.up.right.square").font(.system(size: 10))
                    }
                }
                .buttonStyle(.link)
            }
            .font(.system(size: 13))
        }
    }

    /// "Add http://localhost:4096 [clipboard] as a server" step row.
    private func addServerStepRow(number: Int, key: String, showExternalLink: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            numberBadge(number)
            HStack(spacing: 4) {
                Text("Add").foregroundStyle(.secondary)
                Text("http://localhost:4096")
                clipboardButton("http://localhost:4096", key: key, size: 10)
                if showExternalLink {
                    Button(action: { NSWorkspace.shared.open(URL(string: "http://localhost:4096")!) }) {
                        Image(systemName: "arrow.up.right.square").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Text("as a server").foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
        }
    }

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

    private var openCodeCTAButton: some View {
        Button(action: { state.advance() }) {
            Text("Continue")
                .font(.system(size: 13, weight: .medium))
                .frame(minWidth: 200)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
    }

    // MARK: - Standard layout (all other steps)

    private var standardLayout: some View {
        VStack(spacing: 0) {
            if [.welcome, .microphone, .speechRecognition].contains(state.currentStep) {
                let isLive = state.currentStep == .microphone || state.currentStep == .speechRecognition
                SetupWaveformBanner(audioLevel: micMonitor.audioLevel, liveMode: isLive)
                Spacer(minLength: 28)
            } else if state.currentStep.usesKeyboardIllustration {
                Spacer(minLength: 48)
                keyboardIllustration
                    .padding(.bottom, 24)
            } else {
                Spacer(minLength: 48)
                Image(systemName: state.currentStep.icon)
                    .font(.system(size: 48))
                    .foregroundStyle(iconColor)
                    .frame(height: 60)
                    .padding(.bottom, 24)
            }

            Text(state.currentStep.title)
                .font(.system(size: 20, weight: .semibold))
                .padding(.bottom, 12)

            if !state.currentStep.explanation.isEmpty {
                Text(state.currentStep.explanation)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, state.currentStep.isTryStep ? 16 : 24)
            }

            if state.currentStep == .tryHoldToType {
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
            }

            if state.currentStep == .tryTapToDispatch {
                numberedSteps
                    .padding(.bottom, 20)
            }

            if isCurrentStepGranted {
                permissionGrantedBadge
                    .padding(.bottom, 12)
            }

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

            // tryHoldToType auto-advances on text paste — no button needed
            if state.currentStep != .tryHoldToType {
                actionButton
            }

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

    private var actionButton: some View {
        Button(action: { state.requestCurrentPermission() }) {
            Text(buttonLabel)
                .font(.system(size: 13, weight: .medium))
                .frame(minWidth: 200)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(isContinueDisabled)
    }

    private var iconColor: Color {
        switch state.currentStep {
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
        switch state.currentStep {
        case .microphone where AVCaptureDevice.authorizationStatus(for: .audio) == .denied:
            return "Open Microphone Settings"
        case .speechRecognition where SFSpeechRecognizer.authorizationStatus() == .denied:
            return "Open Speech Settings"
        case .openCodeSetup where state.openCodeOpened:
            return "Continue"
        default:
            return state.currentStep.buttonLabel
        }
    }

    // MARK: - Image loading + shadow trimming

    private static var imageCache: [String: NSImage] = [:]

    private func loadResourceImage(_ name: String) -> NSImage? {
        if let cached = Self.imageCache[name] { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
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
    private var heightSink: AnyCancellable?

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
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
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
    }

    func close() {
        heightSink = nil
        windowController?.window?.close()
        windowController = nil
        state = nil
    }
}
