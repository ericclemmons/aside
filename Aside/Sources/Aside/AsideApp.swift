import SwiftUI
import AppKit

// MARK: - Enums & Preference Keys

enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case dictation
    case whisper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictation: return "Direct Dictation"
        case .whisper: return "Whisper (OpenAI)"
        }
    }

    var description: String {
        switch self {
        case .dictation: return "Uses Apple's built-in speech recognition. Works immediately with no setup."
        case .whisper: return "Uses OpenAI's Whisper model running locally on your Mac. Requires a one-time download."
        }
    }
}

enum HotkeyMode: String, CaseIterable, Identifiable {
    case holdToTalk
    case toggle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .holdToTalk: return "Hold to Type"
        case .toggle: return "Tap to Agent"
        }
    }

    var description: String {
        switch self {
        case .holdToTalk: return "Hold Right ⌥ to record — transcription is typed into the active field on release."
        case .toggle: return "Tap Right ⌥ to start recording, tap again to stop — then choose where to send the prompt."
        }
    }
}

enum EnhancementMode: String, CaseIterable, Identifiable {
    case off
    case appleIntelligence

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .appleIntelligence: return "Apple Intelligence"
        }
    }
}

enum AppPreferenceKey {
    static let transcriptionEngine = "transcriptionEngine"
    static let enhancementMode = "enhancementMode"
    static let enhancementSystemPrompt = "enhancementSystemPrompt"
    static let hotkeyMode = "hotkeyMode"
    static let whisperModelVariant = "whisperModelVariant"

    static let defaultEnhancementPrompt = """
        You are Aside, a speech-to-text transcription assistant. Your only job is to \
        enhance raw transcription output. Fix punctuation, add missing commas, correct \
        capitalization, and improve formatting. Do not alter the meaning, tone, or \
        substance of the text. Do not add, remove, or rephrase any content. Do not \
        add commentary or explanations. Return only the cleaned-up text.
        """
}

// MARK: - App Entry Point

@main
struct AsideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            ContentView(
                whisperModelManager: appDelegate.whisperModelManager,
                historyManager: appDelegate.historyManager,
                customWordsManager: appDelegate.customWordsManager
            )
            .frame(minWidth: 480, maxWidth: 520)
        }
    }
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let speechTranscriber = SpeechTranscriber()
    private var whisperTranscriber: WhisperTranscriber?
    let whisperModelManager = WhisperModelManager()
    let historyManager = TranscriptionHistoryManager()
    let customWordsManager = CustomWordsManager()
    let sessionManager = SessionManager()

    private let hotkeyManager = HotkeyManager()
    private let overlayWindow = RecordingOverlayWindow()
    private let overlayState = OverlayState()
    private var statusItem: NSStatusItem?

    private var enhancer: TextEnhancer?
    private var settingsWindowController: NSWindowController?
    private var setupController: SetupWindowController?

    /// The context captured when recording starts.
    private var capturedContext: ActiveContext?

    /// Screencapture process running while dispatch picker is visible.
    private var screencaptureProcess: Process?
    /// Temp file paths for screenshots taken during the current dispatch session.
    private var screenshotPaths: [String] = []

    /// Recording state machine — single source of truth, no boolean flags.
    private enum RecordingPhase {
        case idle
        case recording           // key held down, recording
        case persistent          // key released with no text, still recording
        case finishingHoldToType // transcriber stopping, will type text
        case finishingDispatch   // transcriber stopping, will show picker
    }
    private var phase: RecordingPhase = .idle


    var transcriptionEngine: TranscriptionEngine {
        get {
            let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.transcriptionEngine)
            return TranscriptionEngine(rawValue: raw ?? "") ?? .dictation
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: AppPreferenceKey.transcriptionEngine)
        }
    }

    private var enhancementMode: EnhancementMode {
        get {
            let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.enhancementMode)
            return EnhancementMode(rawValue: raw ?? "") ?? .off
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: AppPreferenceKey.enhancementMode)
        }
    }

    private var hotkeyMode: HotkeyMode {
        get {
            let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.hotkeyMode)
            return HotkeyMode(rawValue: raw ?? "") ?? .holdToTalk
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: AppPreferenceKey.hotkeyMode)
        }
    }


    /// Derived from phase — no separate boolean.
    private var isSessionActive: Bool { phase != .idle }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if TextEnhancer.isAvailable {
            enhancer = TextEnhancer()
        }

        startOpenCodeServer()
        overlayWindow.observe(state: overlayState)
        setupMenuBar()

        // Show setup window to walk through permissions
        setupController = SetupWindowController()
        setupController?.show(
            onSetupHotkey: { [weak self] _ in
                guard let self else { return }
                if !self.hotkeyManager.isRunning {
                    self.setupHotkey()
                }
            },
            onComplete: { [weak self] in
                guard let self else { return }
                self.setupController = nil
                // Hotkey may already be set up from try steps; ensure it's running
                if !self.hotkeyManager.isRunning {
                    self.setupHotkey()
                }
            }
        )
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            #if DEBUG
            let symbolName = "waveform.circle"   // outline = dev build
            #else
            let symbolName = "waveform.circle.fill"
            #endif
            if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Aside") {
                button.image = img.withSymbolConfiguration(config)
                button.image?.isTemplate = true
            } else {
                button.title = "◉"
            }
        }
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Aside", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func openSettings() {
        if let window = settingsWindowController?.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = ContentView(
            whisperModelManager: whisperModelManager,
            historyManager: historyManager,
            customWordsManager: customWordsManager
        )
        .frame(minWidth: 480, maxWidth: 520)
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 500, height: 400)
        window.center()
        window.title = "Aside Settings"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }

    private func setupHotkey() {
        hotkeyManager.mode = .holdToTalk  // Always raw press/release
        hotkeyManager.onKeyDown = { [weak self] in
            self?.handleKeyDown()
        }
        hotkeyManager.onKeyUp = { [weak self] in
            self?.handleKeyUp()
        }
        hotkeyManager.onCancel = { [weak self] in
            self?.cancelRecording()
        }
        hotkeyManager.start()
    }

    // MARK: - Recording State Machine

    private func handleKeyDown() {
        print("[Recording] handleKeyDown phase=\(phase)")
        switch phase {
        case .idle:
            // Start recording
            startRecording()
            phase = .recording

        case .recording:
            // Shouldn't happen (key already down), ignore
            break

        case .persistent:
            // Second press while recording in persistent mode
            let hasText = !overlayState.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasText {
                // Stop recording and show dispatch picker
                phase = .finishingDispatch
                stopScreenCapture()
                stopTranscriber()
            } else {
                // No text — cancel
                cancelRecording()
            }

        case .finishingHoldToType, .finishingDispatch:
            // Transcriber is stopping, ignore key presses
            break
        }
    }

    private func handleKeyUp() {
        print("[Recording] handleKeyUp phase=\(phase)")
        guard phase == .recording else { return }

        let hasText = !overlayState.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasText {
            // Hold-to-type: stop and deliver
            phase = .finishingHoldToType
            stopTranscriber()
        } else if setupController?.state?.currentStep == .tryHoldToType {
            // During the hold-to-type setup step, a quick tap with no speech is a mistake.
            // Cancel cleanly so the user can try again — don't enter persistent mode.
            cancelRecording()
        } else {
            // No text yet — enter persistent mode (keep recording)
            phase = .persistent
            screenshotPaths = []
            overlayState.screenshotCount = 0
            startScreenCapture()
            // Capture context and refresh sessions async to avoid blocking main thread
            Task {
                let ctx = await Task.detached { ContextCapture.getActiveContext() }.value
                self.capturedContext = ctx
            }
            Task { await sessionManager.refresh() }
        }
    }

    private func startRecording() {
        guard phase == .idle else {
            print("[Recording] BLOCKED — phase=\(phase)")
            return
        }

        // Transition to recording happens in handleKeyDown after this returns
        if transcriptionEngine == .whisper {
            let modelState = whisperModelManager.state
            if case .notDownloaded = modelState {
                print("Whisper model not downloaded, falling back to Direct Dictation")
            } else if case .error = modelState {
                print("Whisper model in error state, falling back to Direct Dictation")
            }
        }

        let words = customWordsManager.words

        if transcriptionEngine == .whisper, isWhisperReady {
            let whisper = whisperTranscriber ?? WhisperTranscriber(modelManager: whisperModelManager)
            whisperTranscriber = whisper
            whisper.customWords = words
            whisper.onTranscriptionFinished = { [weak self] (text: String) in
                guard let self else { return }
                self.processTranscription(text)
            }
            overlayState.bind(to: whisper)
            overlayState.startWaveform()
            whisper.startRecording()
        } else {
            speechTranscriber.customWords = words
            speechTranscriber.onTranscriptionFinished = { [weak self] (text: String) in
                guard let self else { return }
                self.processTranscription(text)
            }
            overlayState.bind(to: speechTranscriber)
            overlayState.startWaveform()
            speechTranscriber.startRecording()
        }
    }

    private var isWhisperReady: Bool {
        switch whisperModelManager.state {
        case .downloaded, .ready, .loading:
            return true
        default:
            return false
        }
    }

    /// Stop the active transcriber (triggers onTranscriptionFinished).
    private func stopTranscriber() {
        if transcriptionEngine == .whisper, isWhisperReady {
            whisperTranscriber?.stopRecording()
            overlayState.isEnhancing = true
        } else {
            speechTranscriber.stopRecording()
        }
    }

    // MARK: - Process Transcription (dual-mode)

    private func processTranscription(_ rawText: String) {
        overlayState.isEnhancing = false
        print("[Transcription] processTranscription called, phase=\(phase), text=\(rawText.prefix(50))")

        guard !rawText.isEmpty else {
            print("[Transcription] Empty text, finishing session")
            finishSession()
            return
        }

        let engine = transcriptionEngine

        // Optionally enhance text first
        if enhancementMode == .appleIntelligence, let enhancer {
            overlayState.isEnhancing = true
            Task {
                let finalText: String
                do {
                    var sysPrompt = UserDefaults.standard.string(forKey: AppPreferenceKey.enhancementSystemPrompt)
                        ?? AppPreferenceKey.defaultEnhancementPrompt
                    let words = self.customWordsManager.words
                    if !words.isEmpty {
                        sysPrompt += "\n\nIMPORTANT: Preserve these custom words exactly: \(words.joined(separator: ", "))."
                    }
                    finalText = try await enhancer.enhance(rawText, systemPrompt: sysPrompt)
                } catch {
                    print("AI enhancement failed: \(error)")
                    finalText = rawText
                }
                self.overlayState.isEnhancing = false
                self.deliverTranscription(finalText, engine: engine, wasEnhanced: finalText != rawText)
            }
        } else {
            deliverTranscription(rawText, engine: engine, wasEnhanced: false)
        }
    }

    /// Route the final text based on the recording phase.
    private func deliverTranscription(_ text: String, engine: TranscriptionEngine, wasEnhanced: Bool) {
        historyManager.addRecord(TranscriptionRecord(text: text, engine: engine, wasEnhanced: wasEnhanced))

        switch phase {
        case .finishingDispatch:
            phase = .idle
            showDispatchPicker(text: text)
        default:
            // Hold-to-type or any other state: type and finish
            phase = .idle
            typeText(text)
            finishSession()
        }
    }

    // MARK: - Hold-to-Talk: Type text via CGEvent (no clipboard)

    private func typeText(_ text: String) {
        guard !text.isEmpty else { return }
        let source = CGEventSource(stateID: .hidSystemState)

        for char in text {
            var utf16 = Array(String(char).utf16)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            keyDown?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            keyUp?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            keyDown?.post(tap: .cgAnnotatedSessionEventTap)
            keyUp?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    // MARK: - Toggle: Dispatch picker

    private func showDispatchPicker(text: String) {
        let context = capturedContext
        let prompt = PromptBuilder.buildPrompt(transcription: text, context: context)

        // Dismiss setup onboarding as soon as the picker appears —
        // the user completed the tap-to-agent flow with the 2nd tap.
        if setupController?.state?.currentStep == .tryTapToDispatch {
            setupController?.state?.markDispatchTested()
        }

        // Build destination list
        var destinations: [DispatchDestination] = [
            .newOpenCode(),
        ]

        // Add existing opencode sessions
        for session in sessionManager.sessions.prefix(5) {
            destinations.append(.openCodeSession(session))
        }

        overlayState.showPicker(destinations: destinations, prompt: prompt) { [weak self] picked, editedPrompt in
            guard let self else { return }

            self.stopScreenCapture()

            // "cancel" is a synthetic destination from Escape key
            guard picked.id != "cancel" else {
                // Delete any screenshots taken during this session
                for path in self.screenshotPaths {
                    try? FileManager.default.removeItem(atPath: path)
                }
                self.screenshotPaths = []
                self.finishSession()
                return
            }

            let finalPrompt = editedPrompt.isEmpty ? prompt : editedPrompt
            let paths = self.screenshotPaths
            self.screenshotPaths = []  // clear so finishSession doesn't delete
            CLIDispatcher.dispatch(prompt: finalPrompt, sessionID: picked.sessionID, filePaths: paths)
            self.finishSession()
        }
    }

    // MARK: - Screenshot capture

    private func startScreenCapture() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let timestamp = formatter.string(from: Date())
        let tempPath = "/tmp/com.ericclemmons.Aside-\(timestamp).png"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-Wo", tempPath]
        process.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.screencaptureProcess = nil
                let exists = FileManager.default.fileExists(atPath: tempPath)
                print("[Screenshot] terminated status=\(proc.terminationStatus) file=\(exists) path=\(tempPath)")
                if exists {
                    self.screenshotPaths.append(tempPath)
                    self.overlayState.screenshotCount = self.screenshotPaths.count
                    print("[Screenshot] collected \(self.screenshotPaths.count) screenshot(s)")
                }
                // Re-spawn only while still in persistent recording
                if self.phase == .persistent {
                    self.startScreenCapture()
                }
            }
        }

        do {
            try process.run()
            screencaptureProcess = process
            print("[Screenshot] screencapture started PID: \(process.processIdentifier)")
        } catch {
            print("[Screenshot] Failed to spawn screencapture: \(error)")
        }
    }

    private func stopScreenCapture() {
        screencaptureProcess?.terminate()
        screencaptureProcess = nil
    }

    // MARK: - Cancel recording (Escape during toggle)

    private func cancelRecording() {
        guard phase != .idle else { return }
        phase = .idle
        hotkeyManager.resetToggle()
        // Stop without delivering — suppress the callback
        if transcriptionEngine == .whisper, isWhisperReady {
            whisperTranscriber?.onTranscriptionFinished = nil
            whisperTranscriber?.stopRecording()
        } else {
            speechTranscriber.onTranscriptionFinished = nil
            speechTranscriber.stopRecording()
        }
        // Clean up any screenshots taken during this session
        for path in screenshotPaths {
            try? FileManager.default.removeItem(atPath: path)
        }
        screenshotPaths = []
        finishSession()
    }

    // MARK: - Session cleanup

    private func finishSession() {
        print("[Recording] finishSession called, phase=\(phase)")
        stopScreenCapture()
        phase = .idle
        overlayState.reset()
        capturedContext = nil
        setupController?.state?.markDispatchTested()
        print("[Recording] finishSession done")
    }

    // MARK: - OpenCode server

    private func startOpenCodeServer() {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/\(NSUserName())"
        let opencodePath = "\(home)/.opencode/bin/opencode"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: opencodePath)
        process.arguments = ["serve", "--port", "4096"]
        process.currentDirectoryURL = URL(fileURLWithPath: home)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        // Inherit PATH so opencode can find its dependencies
        var env = ProcessInfo.processInfo.environment
        if let path = env["PATH"] {
            env["PATH"] = "\(home)/.opencode/bin:/opt/homebrew/bin:/usr/local/bin:\(path)"
        }
        process.environment = env

        do {
            try process.run()
            print("[OpenCode] serve started PID: \(process.processIdentifier)")
        } catch {
            print("[OpenCode] serve failed (may already be running): \(error)")
        }
    }

    // MARK: - Permissions

    @objc private func quit() {
        hotkeyManager.stop()
        NSApp.terminate(nil)
    }

}
