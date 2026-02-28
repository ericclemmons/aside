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
        case .holdToTalk: return "Hold to Talk"
        case .toggle: return "Press to Toggle"
        }
    }

    var description: String {
        switch self {
        case .holdToTalk: return "Hold the hotkey to record, release to stop."
        case .toggle: return "Press the hotkey once to start, press again to stop."
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
                customWordsManager: appDelegate.customWordsManager,
                sessionManager: appDelegate.sessionManager
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

    /// The context captured when recording starts.
    private var capturedContext: ActiveContext?

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

    /// Returns the currently active transcriber based on the user's engine preference.
    private var activeTranscriber: (any TranscriberProtocol)? {
        switch transcriptionEngine {
        case .dictation:
            return speechTranscriber
        case .whisper:
            if whisperTranscriber == nil {
                whisperTranscriber = WhisperTranscriber(modelManager: whisperModelManager)
            }
            return whisperTranscriber
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as an accessory so no Dock icon appears
        NSApp.setActivationPolicy(.accessory)

        // Set up Apple Intelligence enhancer if available
        if TextEnhancer.isAvailable {
            enhancer = TextEnhancer()
        }

        // Menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Aside")
            button.image?.isTemplate = true
        }
        buildMenu()

        Task {
            let granted = await speechTranscriber.requestPermissions()
            if !granted {
                showPermissionAlert()
                return
            }
            setupHotkey()
        }
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
            customWordsManager: customWordsManager,
            sessionManager: sessionManager
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
        let started = hotkeyManager.start()
        if !started {
            showAccessibilityPermissionAlert()
        }

        // Observe changes to hotkey mode preference so it updates at runtime
        hotkeyModeObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.hotkeyManager.mode = self.hotkeyMode
        }
    }

    private func beginRecording() {
        guard !isSessionActive else { return }

        // Capture context from the active window before we start recording
        capturedContext = ContextCapture.getActiveContext()

        // Refresh opencode sessions in the background
        if cliTarget == .opencode {
            Task { await sessionManager.refresh() }
        }

        // If Whisper is selected but the model isn't downloaded yet, fall back to dictation
        if transcriptionEngine == .whisper {
            let modelState = whisperModelManager.state
            if case .notDownloaded = modelState {
                print("Whisper model not downloaded, falling back to Direct Dictation")
            } else if case .error = modelState {
                print("Whisper model in error state, falling back to Direct Dictation")
            }
        }

        isSessionActive = true

        // Pass current custom words to the transcriber
        let words = customWordsManager.words

        // Use the appropriate transcriber
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

    /// Whether the Whisper model is downloaded and available for use.
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
            // For Whisper, transcription happens after stop — the overlay stays visible
            // until onTranscriptionFinished fires via processTranscription
            overlayState.isEnhancing = true // Show processing state while Whisper works
        } else {
            speechTranscriber.stopRecording()
            let waitingForAI = enhancementMode == .appleIntelligence && enhancer != nil
            if !waitingForAI {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.overlayWindow.hide()
                    self?.isSessionActive = false
                }
            }
        }
    }

    private func processTranscription(_ rawText: String) {
        // Clear the "processing" state from Whisper
        overlayState.isEnhancing = false

        guard !rawText.isEmpty else {
            overlayWindow.hide()
            isSessionActive = false
            return
        }

        let engine = transcriptionEngine
        let context = capturedContext
        let target = cliTarget
        let sessionID = sessionManager.selectedSessionID

        // Build prompt with context
        let prompt = PromptBuilder.buildPrompt(transcription: rawText, context: context)

        if enhancementMode == .appleIntelligence, let enhancer {
            overlayState.isEnhancing = true
            if transcriptionEngine == .whisper {
                whisperTranscriber?.isEnhancing = true
            } else {
                speechTranscriber.isEnhancing = true
            }
            Task {
                defer {
                    self.overlayState.isEnhancing = false
                    if self.transcriptionEngine == .whisper {
                        self.whisperTranscriber?.isEnhancing = false
                    } else {
                        self.speechTranscriber.isEnhancing = false
                    }
                    self.overlayWindow.hide()
                    self.isSessionActive = false
                    self.capturedContext = nil
                }
                do {
                    var sysPrompt = UserDefaults.standard.string(forKey: AppPreferenceKey.enhancementSystemPrompt)
                        ?? AppPreferenceKey.defaultEnhancementPrompt
                    let words = self.customWordsManager.words
                    if !words.isEmpty {
                        sysPrompt += "\n\nIMPORTANT: The following are custom words, names, or abbreviations the user has defined. Always preserve their exact spelling and casing: \(words.joined(separator: ", "))."
                    }
                    let enhanced = try await enhancer.enhance(rawText, systemPrompt: sysPrompt)
                    let enhancedPrompt = PromptBuilder.buildPrompt(transcription: enhanced, context: context)
                    CLIDispatcher.dispatch(prompt: enhancedPrompt, target: target, sessionID: sessionID)
                    self.historyManager.addRecord(
                        TranscriptionRecord(text: enhanced, engine: engine, wasEnhanced: true)
                    )
                } catch {
                    print("AI enhancement failed, using raw text: \(error)")
                    CLIDispatcher.dispatch(prompt: prompt, target: target, sessionID: sessionID)
                    self.historyManager.addRecord(
                        TranscriptionRecord(text: rawText, engine: engine, wasEnhanced: false)
                    )
                }
            }
        } else {
            CLIDispatcher.dispatch(prompt: prompt, target: target, sessionID: sessionID)
            historyManager.addRecord(
                TranscriptionRecord(text: rawText, engine: engine, wasEnhanced: false)
            )
            overlayWindow.hide()
            isSessionActive = false
            capturedContext = nil
        }
    }

    @objc private func quit() {
        hotkeyManager.stop()
        NSApp.terminate(nil)
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Permissions Required"
        alert.informativeText = "Aside needs Microphone and Speech Recognition access. Please grant them in System Settings > Privacy & Security."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!)
        }
        NSApp.terminate(nil)
    }

    private func showAccessibilityPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Aside needs Accessibility access to detect the Right Option key system-wide. Please enable Aside in System Settings > Privacy & Security > Accessibility, then relaunch the app."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        NSApp.terminate(nil)
    }
}
