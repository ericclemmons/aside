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
            .environment(\.colorScheme, .dark)
            .preferredColorScheme(.dark)
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
    let openCodeConfig = OpenCodeConfig()
    lazy var sessionManager = SessionManager(config: openCodeConfig)

    private let hotkeyManager = HotkeyManager()
    private let overlayWindow = RecordingOverlayWindow()
    private let overlayState = OverlayState()
    private var statusItem: NSStatusItem?

    private var enhancer: TextEnhancer?
    private var settingsWindowController: NSWindowController?
    private var setupController: SetupWindowController?
    private var appObserverTokens: [Any] = []
    private var discoveryTimer: Timer?

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
        enforceDarkAppearance()
        appObserverTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.enforceDarkAppearance()
            }
        )

        if TextEnhancer.isAvailable {
            enhancer = TextEnhancer()
        }

        openCodeConfig.discover()
        overlayWindow.observe(state: overlayState)
        setupMenuBar()

        // Show setup window to walk through permissions
        setupController = SetupWindowController()
        setupController?.show(
            openCodeConfig: openCodeConfig,
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

        // Re-apply once windows are visible.
        DispatchQueue.main.async { [weak self] in
            self?.enforceDarkAppearance()
        }
    }

    private func enforceDarkAppearance() {
        guard let appearance = NSAppearance(named: .darkAqua) else { return }
        NSApp.appearance = appearance
        for window in NSApp.windows {
            window.appearance = appearance
            window.contentView?.appearance = appearance
            window.contentViewController?.view.appearance = appearance
        }
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
        menu.delegate = self
        statusItem?.menu = menu

        // Discover periodically
        discoveryTimer?.invalidate()
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openCodeConfig.discover()
            }
        }
    }

    /// Rebuild menu items on every open — reflects live connection state.
    fileprivate func rebuildMenuItems(_ menu: NSMenu) {
        menu.removeAllItems()

        let statusColor: NSColor = openCodeConfig.server != nil ? .systemGreen : .systemRed
        let statusConfig = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [statusColor]))
        let headerItem = NSMenuItem(title: "OpenCode Desktop", action: #selector(openOpenCodeDesktop), keyEquivalent: "")
        headerItem.target = self
        headerItem.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(statusConfig)
        menu.addItem(headerItem)

        if openCodeConfig.server != nil {
            let attachItem = NSMenuItem()
            attachItem.attributedTitle = NSAttributedString(
                string: "opencode attach …",
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]
            )
            attachItem.action = #selector(attachWithCLI)
            attachItem.target = self
            attachItem.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
            menu.addItem(attachItem)
        }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let quitItem = NSMenuItem(title: "Quit Aside (v\(version))", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        menu.addItem(quitItem)
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
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 500, height: 400)
        window.center()
        window.title = "Aside Settings"
        window.contentViewController = hostingController
        window.contentView?.appearance = NSAppearance(named: .darkAqua)
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
        guard let server = openCodeConfig.server else {
            print("[Dispatch] No OpenCode Desktop server found, skipping dispatch")
            finishSession()
            return
        }

        let context = capturedContext
        let prompt = PromptBuilder.buildPrompt(transcription: text, context: context)
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/\(NSUserName())"

        // Dismiss setup onboarding as soon as the picker appears —
        // the user completed the tap-to-agent flow with the 2nd tap.
        if setupController?.state?.currentStep == .tryTapToDispatch {
            setupController?.state?.markDispatchTested()
        }

        // Build destination list
        var destinations: [DispatchDestination] = []

        // Collect unique directories from recent sessions, ordered by most recent
        var seenDirs = Set<String>()
        var newSessionDirs: [(display: String, full: String)] = []
        for session in sessionManager.sessions {
            guard let dir = session.directory, !seenDirs.contains(dir) else { continue }
            seenDirs.insert(dir)
            newSessionDirs.append((SessionManager.abbreviateHome(in: dir), dir))
        }
        // Always include the current project dir if not already covered
        let projectDir = sessionManager.currentProjectDirectory ?? home
        if !seenDirs.contains(projectDir) {
            newSessionDirs.insert((SessionManager.abbreviateHome(in: projectDir), projectDir), at: 0)
        }

        destinations.append(.sectionHeader("New Session"))
        for dir in newSessionDirs {
            destinations.append(.newOpenCodeWorkspace(displayDirectory: dir.display, workingDirectory: dir.full))
        }

        // Add existing opencode sessions
        let recentSessions = Array(sessionManager.sessions.prefix(5))
        destinations.append(.sectionHeader("Last \(recentSessions.count) Sessions"))
        for session in recentSessions {
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
            CLIDispatcher.dispatch(
                prompt: finalPrompt,
                server: server,
                sessionID: picked.sessionID,
                filePaths: paths,
                workingDirectory: picked.workingDirectory
            )
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
        process.arguments = ["-i", tempPath]
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

    @objc private func openOpenCodeWeb() {
        guard let server = openCodeConfig.server,
              let url = URL(string: "http://\(server.username):\(server.password)@\(server.host):\(server.port)")
        else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openOpenCodeDesktop() {
        let appURL = URL(fileURLWithPath: "/Applications/OpenCode.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.open(appURL)
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "OpenCode"]
            try? process.run()
        }
    }

    @objc private func attachWithCLI() {
        guard let server = openCodeConfig.server else { return }
        let command = "opencode attach \(server.attachTarget) -p \(server.password)"
        // Copy to pasteboard instead of typing — typeText can mangle UUIDs
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        // Deactivate Aside so keystrokes go to the previously focused app
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            // Paste (Cmd+V) then Enter
            self?.pasteAndEnter()
        }
    }

    private func pasteAndEnter() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Cmd+V
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) // 9 = V
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cgAnnotatedSessionEventTap)
        vUp?.post(tap: .cgAnnotatedSessionEventTap)
        // Enter after a tiny delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)
            let enterUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
            enterDown?.post(tap: .cgAnnotatedSessionEventTap)
            enterUp?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    // MARK: - Permissions

    @objc private func quit() {
        hotkeyManager.stop()
        discoveryTimer?.invalidate()
        discoveryTimer = nil
        for token in appObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
        appObserverTokens.removeAll()
        NSApp.terminate(nil)
    }

}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenuItems(menu)
    }
}
