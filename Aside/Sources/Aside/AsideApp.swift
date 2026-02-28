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
        case .toggle: return "Tap to Dispatch"
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
    static let cliTarget = "cliTarget"

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

    /// Which hotkey mode was active when the current session started.
    private var activeSessionMode: HotkeyMode = .holdToTalk

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

    var cliTarget: CLITarget {
        get {
            let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.cliTarget)
            return CLITarget(rawValue: raw ?? "") ?? .claude
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: AppPreferenceKey.cliTarget)
        }
    }

    private var hotkeyModeObserver: NSObjectProtocol?
    private var isSessionActive = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if TextEnhancer.isAvailable {
            enhancer = TextEnhancer()
        }

        setupMenuBar()

        // Show setup window to walk through permissions
        setupController = SetupWindowController()
        setupController?.show(
            onSetupHotkey: { [weak self] in
                self?.setupHotkey()
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
            // Use SF Symbol directly as NSImage
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            if let img = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Aside") {
                button.image = img.withSymbolConfiguration(config)
                button.image?.isTemplate = true
            } else {
                // Fallback: text-based
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
        hotkeyManager.mode = hotkeyMode
        hotkeyManager.onKeyDown = { [weak self] in
            self?.beginRecording()
        }
        hotkeyManager.onKeyUp = { [weak self] in
            self?.endRecording()
        }
        hotkeyManager.start()

        hotkeyModeObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.hotkeyManager.mode = self.hotkeyMode
        }
    }

    // MARK: - Recording Flow

    private func beginRecording() {
        guard !isSessionActive else { return }

        activeSessionMode = hotkeyMode

        // Only capture context and fetch sessions for dispatch mode
        if activeSessionMode == .toggle {
            capturedContext = ContextCapture.getActiveContext()
            Task { await sessionManager.refresh() }
        }

        if transcriptionEngine == .whisper {
            let modelState = whisperModelManager.state
            if case .notDownloaded = modelState {
                print("Whisper model not downloaded, falling back to Direct Dictation")
            } else if case .error = modelState {
                print("Whisper model in error state, falling back to Direct Dictation")
            }
        }

        isSessionActive = true
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
            overlayWindow.show(state: overlayState)
            whisper.startRecording()
        } else {
            speechTranscriber.customWords = words
            speechTranscriber.onTranscriptionFinished = { [weak self] (text: String) in
                guard let self else { return }
                self.processTranscription(text)
            }
            overlayState.bind(to: speechTranscriber)
            overlayWindow.show(state: overlayState)
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

    private func endRecording() {
        guard isSessionActive else { return }

        if transcriptionEngine == .whisper, isWhisperReady {
            whisperTranscriber?.stopRecording()
            overlayState.isEnhancing = true
        } else {
            speechTranscriber.stopRecording()
            // For hold-to-talk with dictation, give a short delay for final result
            if activeSessionMode == .holdToTalk {
                let waitingForAI = enhancementMode == .appleIntelligence && enhancer != nil
                if !waitingForAI {
                    // processTranscription will be called by onTranscriptionFinished
                }
            }
        }
    }

    // MARK: - Process Transcription (dual-mode)

    private func processTranscription(_ rawText: String) {
        overlayState.isEnhancing = false

        guard !rawText.isEmpty else {
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

    /// Route the final text based on the active hotkey mode.
    private func deliverTranscription(_ text: String, engine: TranscriptionEngine, wasEnhanced: Bool) {
        historyManager.addRecord(TranscriptionRecord(text: text, engine: engine, wasEnhanced: wasEnhanced))

        switch activeSessionMode {
        case .holdToTalk:
            // Type directly into the active text field via CGEvent
            typeText(text)
            finishSession()

        case .toggle:
            // Show the dispatch picker
            showDispatchPicker(text: text)
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

        // Build destination list
        var destinations: [DispatchDestination] = [
            .newClaude(),
            .newOpenCode(),
        ]

        // Add existing opencode sessions
        for session in sessionManager.sessions.prefix(5) {
            destinations.append(.openCodeSession(session))
        }

        overlayState.showPicker(destinations: destinations) { [weak self] picked in
            guard let self else { return }

            // "cancel" is a synthetic destination from Escape key
            guard picked.id != "cancel" else {
                self.finishSession()
                return
            }

            CLIDispatcher.dispatch(prompt: prompt, target: picked.target, sessionID: picked.sessionID)
            self.finishSession()
        }

        overlayWindow.enableKeyboardNavigation(state: overlayState)
    }

    // MARK: - Session cleanup

    private func finishSession() {
        overlayWindow.hide()
        overlayState.reset()
        isSessionActive = false
        capturedContext = nil
    }

    // MARK: - Permissions

    @objc private func quit() {
        hotkeyManager.stop()
        NSApp.terminate(nil)
    }

}
