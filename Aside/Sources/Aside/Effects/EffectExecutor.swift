import Foundation
import AppKit
import AsideCore

/// Maps Effect values to actual service calls, feeding resulting events back to the store.
@MainActor
final class EffectExecutor {
    private let store: AppStore

    // Services (injected after init)
    var permissionService: PermissionService?
    var transcriptionService: TranscriptionService?
    var screenCaptureService: (any ScreenCaptureServiceProtocol)?
    var contextCaptureService: ContextCaptureService?
    var dispatchService: DispatchService?
    var openCodeService: OpenCodeService?
    var hotkeyService: HotkeyService?
    var historyManager: TranscriptionHistoryManager?
    var overlayWindow: RecordingOverlayWindow?
    var overlayState: OverlayState?
    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    var enhancer: TextEnhancer? {
        get { _enhancer as? TextEnhancer }
        set { _enhancer = newValue }
    }
    #endif
    private var _enhancer: Any?
    var customWordsManager: CustomWordsManager?

    init(store: AppStore) {
        self.store = store
        store.effectHandler = { [weak self] effect, callback in
            self?.execute(effect, callback: callback)
        }
    }

    func execute(_ effect: Effect, callback: @escaping (AppEvent) -> Void) {
        switch effect {
        case .startRecording(let engine):
            let words = customWordsManager?.words ?? []
            transcriptionService?.startRecording(engine: engine, customWords: words)
            // Set up transcription callbacks
            transcriptionService?.onTranscriptionUpdate = { text, level in
                callback(.transcriptionUpdated(text: text, audioLevel: level))
            }
            transcriptionService?.onTranscriptionFinished = { text in
                callback(.transcriptionFinished(text: text))
            }

        case .stopRecording:
            transcriptionService?.stopRecording()

        case .cancelRecording:
            transcriptionService?.cancelRecording()

        case .typeText(let text):
            typeText(text)

        case .enhanceText(let text):
            Task {
                #if canImport(FoundationModels)
                if #available(macOS 26.0, *), let enhancer = self.enhancer {
                    do {
                        var sysPrompt = UserDefaults.standard.string(forKey: AppPreferenceKey.enhancementSystemPrompt)
                            ?? AppPreferenceKey.defaultEnhancementPrompt
                        let words = customWordsManager?.words ?? []
                        if !words.isEmpty {
                            sysPrompt += "\n\nIMPORTANT: Preserve these custom words exactly: \(words.joined(separator: ", "))."
                        }
                        let enhanced = try await enhancer.enhance(text, systemPrompt: sysPrompt)
                        callback(.enhancementFinished(text: enhanced))
                        return
                    } catch {
                        NSLog("[EffectExecutor] Enhancement failed: \(error)")
                    }
                }
                #endif
                callback(.enhancementFinished(text: text))
            }

        case .startScreenCapture:
            // Only spawn screencapture if screen recording permission is confirmed.
            // Without it, macOS shows a blocking TCC dialog every time.
            guard permissionService?.hasScreenRecording == true else {
                NSLog("[EffectExecutor] Skipping screen capture — no screen recording permission")
                break
            }
            screenCaptureService?.startCapture { path in
                callback(.screenshotCaptured(path: path))
            }

        case .stopScreenCapture:
            screenCaptureService?.stopCapture()

        case .captureContext:
            Task {
                let ctx = await contextCaptureService?.capture()
                if let ctx {
                    callback(.contextCaptured(ctx))
                }
            }

        case .checkPermissions:
            let status = permissionService?.checkAll() ?? PermissionStatus()
            callback(.permissionsChecked(status))

        case .requestPermission(let perm):
            Task {
                let granted = await permissionService?.request(perm) ?? false
                if granted {
                    callback(.permissionGranted(perm))
                }
            }

        case .startPermissionPolling:
            // Poll permissions every second (mic, speech, screen recording)
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                let status = self.permissionService?.checkAll() ?? PermissionStatus()
                callback(.permissionsChecked(status))
                if status.allGranted {
                    timer.invalidate()
                }
            }
            // Also listen for accessibility changes via distributed notification
            permissionService?.observeAccessibilityChanges { [weak self] in
                guard let self else { return }
                let status = self.permissionService?.checkAll() ?? PermissionStatus()
                callback(.permissionsChecked(status))
            }

        case .startDesktopServerDiscovery:
            openCodeService?.startDesktopDiscovery { server in
                callback(.desktopServerDiscovered(server))
            }

        case .refreshSessions:
            Task {
                let activeServer = self.store.context.server
                guard let result = await openCodeService?.refreshSessions(server: activeServer) else { return }
                callback(.sessionsRefreshed(sessions: result.sessions, projectDirectory: result.projectDirectory))
            }

        case .dispatch(let prompt, let server, let sessionID, let files, let workDir):
            dispatchService?.dispatch(prompt: prompt, server: server, sessionID: sessionID, filePaths: files, workingDirectory: workDir)

        case .buildDestinations:
            let destinations = buildDestinationList()
            store.updateContext { ctx in
                ctx.destinations = destinations
                // Default to "New Session in <projectDir>" — the first newSessionWorkspace entry
                ctx.selectedDestinationIndex = destinations.firstIndex(where: { $0.kind == .newSessionWorkspace }) ?? 0
            }

        case .showOverlay(let overlayEffect):
            switch overlayEffect {
            case .waveform:
                overlayState?.mode = .waveform
            case .picker:
                overlayState?.mode = .picker
            }

        case .hideOverlay:
            overlayState?.reset()

        case .deleteFiles(let paths):
            for path in paths {
                try? FileManager.default.removeItem(atPath: path)
            }

        case .addHistory(let text, let engine, let enhanced):
            historyManager?.addRecord(TranscriptionRecord(text: text, engine: engine, wasEnhanced: enhanced))

        case .startHotkey:
            NSLog("[EffectExecutor] Starting hotkey service (nil=%d)", hotkeyService == nil ? 1 : 0)
            hotkeyService?.start { [weak self] event in
                NSLog("[EffectExecutor] Hotkey event: %@", String(describing: event))
                self?.store.send(event)
            }
        }
    }

    // MARK: - Type text via CGEvent

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

        if UserDefaults.standard.bool(forKey: AppPreferenceKey.autoSubmit) {
            let returnDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
            let returnUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
            returnDown?.post(tap: .cgAnnotatedSessionEventTap)
            returnUp?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    // MARK: - Build destination list

    private func buildDestinationList() -> [DispatchDestination] {
        let threeDaysAgo = Date().addingTimeInterval(-3 * 24 * 3600)
        let sessions = store.context.sessions.filter { $0.directory != "/" && $0.updatedAt > threeDaysAgo }
        let recentSessions = Array(sessions.prefix(5))

        var destinations: [DispatchDestination] = []

        // 1. Previous sessions sorted ascending (oldest first, newest near bottom)
        for session in recentSessions.reversed() {
            destinations.append(.openCodeSession(session))
        }

        // 2. "New Session" entries from unique workspace directories (deduped, ordered by most recent)
        // Normalize ~ to full path for dedup since API returns both forms
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/\(NSUserName())"
        var seenDirs = Set<String>()
        for session in sessions {
            guard var dir = session.directory else { continue }
            if dir.hasPrefix("~/") {
                dir = home + dir.dropFirst(1)
            } else if dir == "~" {
                dir = home
            }
            guard seenDirs.insert(dir).inserted else { continue }
            destinations.append(.newOpenCodeWorkspace(
                displayDirectory: Session.abbreviateHome(in: dir),
                workingDirectory: dir
            ))
        }

        return destinations
    }
}
