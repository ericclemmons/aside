import SwiftUI
import AppKit
import Combine
import AsideCore

// MARK: - App Entry Point

@main
struct AsideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(customWordsManager: appDelegate.customWordsManager)
            .frame(minWidth: 480, maxWidth: 520)
            .environment(\.colorScheme, .dark)
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // Store — starts in onboardingPermissions; setup wizard handles skip-if-granted
    let store = AppStore(phase: .onboardingPermissions, context: AppContext(
        selectedServerTarget: {
            let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.selectedServerTarget)
            return ServerTarget(rawValue: raw ?? "") ?? .aside
        }(),
        transcriptionEngine: {
            let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.transcriptionEngine)
            return TranscriptionEngine(rawValue: raw ?? "") ?? .dictation
        }(),
        enhancementMode: TextEnhancer.isAvailable ? .appleIntelligence : .off
    ))

    // Services
    let transcriptionService = TranscriptionService()
    let historyManager = TranscriptionHistoryManager()
    let customWordsManager = CustomWordsManager()
    private let permissionService = PermissionService()
    private let screenCaptureService = ScreenCaptureService()
    private let contextCaptureService = ContextCaptureService()
    private let dispatchService = DispatchService()
    private let openCodeService = OpenCodeService()
    private let hotkeyService = HotkeyService()

    // UI
    private let overlayWindow = RecordingOverlayWindow()
    private let overlayState = OverlayState()
    private var statusItem: NSStatusItem?
    private var settingsWindowController: NSWindowController?
    private var storeSetupController: StoreSetupWindowController?
    private var appObserverTokens: [Any] = []

    // Effect executor
    private var executor: EffectExecutor!

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

        // Sync Settings changes (UserDefaults) → store
        appObserverTokens.append(
            UserDefaults.standard.observe(\.transcriptionEngine, options: [.new]) { [weak self] _, change in
                guard let raw = change.newValue, let engine = TranscriptionEngine(rawValue: raw) else { return }
                Task { @MainActor [weak self] in
                    self?.store.updateContext { $0.transcriptionEngine = engine }
                }
            }
        )

        // Wire effect executor
        executor = EffectExecutor(store: store)
        executor.permissionService = permissionService
        executor.transcriptionService = transcriptionService
        executor.screenCaptureService = screenCaptureService
        executor.contextCaptureService = contextCaptureService
        executor.dispatchService = dispatchService
        executor.openCodeService = openCodeService
        executor.hotkeyService = hotkeyService
        executor.historyManager = historyManager
        executor.overlayWindow = overlayWindow
        executor.overlayState = overlayState
        executor.customWordsManager = customWordsManager
        if TextEnhancer.isAvailable {
            executor.enhancer = TextEnhancer()
        }

        // Wire overlay to show store state
        overlayWindow.observe(state: overlayState)
        bindStoreToOverlay()

        setupMenuBar()

        // Preflight: synchronous desktop server discovery so setup window knows connection state
        if let desktop = OpenCodeConfig.findDesktopServer() {
            store.send(.desktopServerDiscovered(desktop))
        }

        // Show setup window — reads store.phase, auto-closes on transition to idle
        storeSetupController = StoreSetupWindowController()
        storeSetupController?.show(store: store, permissionService: permissionService)

        // Start ongoing server discovery + permission polling
        store.send(.appLaunched)

        DispatchQueue.main.async { [weak self] in
            self?.enforceDarkAppearance()
        }
    }

    /// Sync store state changes → overlay state for the overlay window.
    private func bindStoreToOverlay() {
        // Transcription updates → overlay
        store.$context
            .receive(on: RunLoop.main)
            .sink { [weak self] ctx in
                guard let self else { return }
                self.overlayState.transcribedText = ctx.transcribedText
                self.overlayState.audioLevel = ctx.audioLevel
                self.overlayState.isEnhancing = ctx.isEnhancing
                self.overlayState.screenshotCount = ctx.screenshotPaths.count
                if !ctx.destinations.isEmpty && self.overlayState.destinations.isEmpty {
                    self.overlayState.destinations = ctx.destinations
                    self.overlayState.selectedIndex = ctx.selectedDestinationIndex
                }
            }
            .store(in: &cancellables)

        // Picker callbacks → store
        overlayState.onDestinationPicked = { [weak self] dest, editedPrompt in
            guard let self else { return }
            if dest.id == "cancel" {
                self.store.send(.dispatchCancelled)
            } else {
                self.store.send(.destinationPicked(dest, editedPrompt: editedPrompt))
            }
            // If in onboarding tap-to-dispatch, completing a dispatch transitions to idle
            if self.store.phase == .onboardingTryTapToDispatch {
                self.store.send(.dispatchComplete)
            }
        }
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Appearance

    private func enforceDarkAppearance() {
        guard let appearance = NSAppearance(named: .darkAqua) else { return }
        NSApp.appearance = appearance
        for window in NSApp.windows {
            window.appearance = appearance
            window.contentView?.appearance = appearance
            window.contentViewController?.view.appearance = appearance
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            #if DEBUG
            let symbolName = "waveform.circle"
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
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    fileprivate func rebuildMenuItems(_ menu: NSMenu) {
        menu.removeAllItems()

        // MARK: Transcription engine selector
        let transcribeHeader = NSMenuItem(title: "Transcribe with", action: nil, keyEquivalent: "")
        transcribeHeader.isEnabled = false
        transcribeHeader.attributedTitle = NSAttributedString(
            string: "Transcribe with",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        menu.addItem(transcribeHeader)

        let currentEngine = store.context.transcriptionEngine
        for engine in TranscriptionEngine.allCases {
            let item = NSMenuItem(title: engine.menuTitle, action: #selector(selectEngine(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = engine.rawValue
            item.state = engine == currentEngine ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // MARK: Server selector header
        let headerItem = NSMenuItem(title: "Server", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        headerItem.attributedTitle = NSAttributedString(
            string: "Server",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        menu.addItem(headerItem)

        let selectedTarget = store.context.selectedServerTarget

        let asideItem = makeServerMenuItem(
            label: "Aside",
            port: OpenCodeService.asidePort,
            server: store.context.asideServer,
            isSelected: selectedTarget == .aside,
            target: .aside
        )
        menu.addItem(asideItem)

        let desktopItem = makeServerMenuItem(
            label: "OpenCode Desktop",
            port: store.context.desktopServer?.port,
            server: store.context.desktopServer,
            isSelected: selectedTarget == .desktop,
            target: .desktop
        )
        menu.addItem(desktopItem)

        menu.addItem(NSMenuItem.separator())

        // Attach submenu (only if connected)
        let isConnected = store.context.openCodeConnected
        if isConnected {
            let attachItem = NSMenuItem()
            attachItem.attributedTitle = NSAttributedString(
                string: "opencode attach …",
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]
            )
            attachItem.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)

            let submenu = NSMenu()
            attachItem.submenu = submenu
            let loadingItem = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            submenu.addItem(loadingItem)

            Task {
                let allProjects = await self.fetchProjects()
                let oneWeekAgo = Date().addingTimeInterval(-7 * 86400)
                var projects = allProjects.filter { $0.updatedAt >= oneWeekAgo }
                if projects.isEmpty, let first = allProjects.first { projects = [first] }

                if projects.count == 1 {
                    attachItem.submenu = nil
                    attachItem.action = #selector(self.attachToProject(_:))
                    attachItem.target = self
                    attachItem.representedObject = projects[0].worktree
                } else if projects.isEmpty {
                    submenu.removeAllItems()
                    let emptyItem = NSMenuItem(title: "No projects", action: nil, keyEquivalent: "")
                    emptyItem.isEnabled = false
                    submenu.addItem(emptyItem)
                } else {
                    submenu.removeAllItems()
                    for project in projects {
                        let item = self.makeProjectMenuItem(project)
                        submenu.addItem(item)
                    }
                }
            }

            menu.addItem(attachItem)
            menu.addItem(NSMenuItem.separator())
        }

        let settingsItem = NSMenuItem(title: "Vocabulary...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "text.book.closed", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let quitItem = NSMenuItem(title: "Quit Aside (v\(version))", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        menu.addItem(quitItem)
    }

    private func makeServerMenuItem(label: String, port: Int?, server: DiscoveredServer?, isSelected: Bool, target: ServerTarget) -> NSMenuItem {
        let portSuffix = (server != nil && port != nil) ? " (\(port!))" : " (Not Started)"
        let item = NSMenuItem(title: label + portSuffix, action: #selector(selectServer(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = target.rawValue
        item.state = isSelected ? .on : .off

        // Label normal, port muted
        let attrTitle = NSMutableAttributedString()
        attrTitle.append(NSAttributedString(string: label, attributes: [
            .font: NSFont.menuFont(ofSize: 13)
        ]))
        attrTitle.append(NSAttributedString(string: portSuffix, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]))
        item.attributedTitle = attrTitle
        return item
    }

    @objc private func selectServer(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let target = ServerTarget(rawValue: rawValue) else { return }
        UserDefaults.standard.set(target.rawValue, forKey: AppPreferenceKey.selectedServerTarget)
        store.send(.serverTargetChanged(target))
    }

    @objc private func selectEngine(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let engine = TranscriptionEngine(rawValue: rawValue) else { return }
        UserDefaults.standard.set(engine.rawValue, forKey: AppPreferenceKey.transcriptionEngine)
        store.updateContext { $0.transcriptionEngine = engine }
    }

    // MARK: - Actions

    @objc private func openSettings() {
        if let window = settingsWindowController?.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = SettingsView(customWordsManager: customWordsManager)
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

    @objc private func attachToProject(_ sender: NSMenuItem) {
        guard let dir = sender.representedObject as? String else { return }
        guard let server = store.context.server else { return }
        let attachDir = (dir == "/") ? "~" : dir
        var command = ""
        if !server.username.isEmpty && !server.password.isEmpty {
            command += "OPENCODE_SERVER_USERNAME=\(server.username) OPENCODE_SERVER_PASSWORD=\(server.password) "
        }
        command += "opencode attach \(server.attachTarget) --dir \(attachDir) --continue"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.pasteAndEnter()
        }
    }

    private func makeProjectMenuItem(_ project: ProjectInfo) -> NSMenuItem {
        let dir = project.id == "global" ? "~" : Session.abbreviateHome(in: project.worktree)
        let timeAgo = project.timeAgo

        // Use a tab character to right-align the time, like keyboard shortcuts
        let title = "\(dir)\t\(timeAgo)"
        let item = NSMenuItem(title: title, action: #selector(attachToProject(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = project.worktree

        // Styled: dir normal, time muted
        let attrTitle = NSMutableAttributedString()
        attrTitle.append(NSAttributedString(string: dir, attributes: [
            .font: NSFont.menuFont(ofSize: 13)
        ]))
        attrTitle.append(NSAttributedString(string: "\t\(timeAgo)", attributes: [
            .font: NSFont.menuFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]))
        item.attributedTitle = attrTitle

        return item
    }

    private struct ProjectInfo {
        let id: String
        let worktree: String
        let updatedAt: Date

        var timeAgo: String {
            let interval = Date().timeIntervalSince(updatedAt)
            if interval < 60 { return "just now" }
            if interval < 3600 { return "\(Int(interval / 60))m ago" }
            if interval < 86400 { return "\(Int(interval / 3600))h ago" }
            return "\(Int(interval / 86400))d ago"
        }
    }

    private func fetchProjects() async -> [ProjectInfo] {
        guard let server = store.context.server else { return [] }
        var request = server.authenticatedRequest(path: "/project")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
            var projects = json.compactMap { obj -> ProjectInfo? in
                guard let worktree = obj["worktree"] as? String else { return nil }
                let id = obj["id"] as? String ?? ""
                let time = obj["time"] as? [String: Any]
                let updatedMs = time?["updated"] as? Double ?? 0
                return ProjectInfo(id: id, worktree: worktree, updatedAt: Date(timeIntervalSince1970: updatedMs / 1000))
            }
            projects.sort { $0.updatedAt > $1.updatedAt }
            return projects
        } catch {
            NSLog("[Aside] Failed to fetch projects: %@", error.localizedDescription)
            return []
        }
    }

    private func pasteAndEnter() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cgAnnotatedSessionEventTap)
        vUp?.post(tap: .cgAnnotatedSessionEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)
            let enterUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
            enterDown?.post(tap: .cgAnnotatedSessionEventTap)
            enterUp?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    @objc private func quit() {
        hotkeyService.stop()
        openCodeService.stopDiscovery()
        openCodeService.stopServer()
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

// MARK: - KVO for UserDefaults

extension UserDefaults {
    @objc dynamic var transcriptionEngine: String {
        string(forKey: AppPreferenceKey.transcriptionEngine) ?? TranscriptionEngine.dictation.rawValue
    }
}
