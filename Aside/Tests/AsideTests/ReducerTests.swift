import XCTest
@testable import AsideCore

final class ReducerTests: XCTestCase {

    // MARK: - Helpers

    private func send(_ event: AppEvent, phase: AppPhase, context: inout AppContext) -> (AppPhase, [Effect]) {
        reduce(phase: phase, context: &context, event: event)
    }

    private func makeContext(
        transcribedText: String = "",
        engine: TranscriptionEngine = .dictation,
        enhancement: EnhancementMode = .off,
        server: DiscoveredServer? = nil,
        screenshotPaths: [String] = []
    ) -> AppContext {
        AppContext(
            server: server,
            transcribedText: transcribedText,
            screenshotPaths: screenshotPaths,
            transcriptionEngine: engine,
            enhancementMode: enhancement,
            openCodeConnected: server != nil
        )
    }

    private let testServer = DiscoveredServer(host: "127.0.0.1", port: 4096, username: "user", password: "pass")

    // MARK: - App Lifecycle

    func testAppLaunched() {
        var ctx = makeContext()
        let (phase, effects) = send(.appLaunched, phase: .idle, context: &ctx)
        XCTAssertEqual(phase, .idle)
        XCTAssertTrue(effects.contains(.checkPermissions))
        XCTAssertTrue(effects.contains(.startAsideServer))
    }

    // MARK: - Onboarding: Permissions

    func testOnboardingPermissionsChecked() {
        var ctx = makeContext()
        let status = PermissionStatus(screenRecording: true, microphone: true)
        let (phase, _) = send(.permissionsChecked(status), phase: .onboardingPermissions, context: &ctx)
        XCTAssertEqual(phase, .onboardingPermissions)
        XCTAssertTrue(ctx.permissions.screenRecording)
        XCTAssertTrue(ctx.permissions.microphone)
        XCTAssertFalse(ctx.permissions.accessibility)
    }

    func testOnboardingPermissionGranted() {
        var ctx = makeContext()
        let (phase, effects) = send(.permissionGranted(.microphone), phase: .onboardingPermissions, context: &ctx)
        XCTAssertEqual(phase, .onboardingPermissions)
        XCTAssertTrue(ctx.permissions.microphone)
        XCTAssertTrue(effects.contains(.checkPermissions))
    }

    func testOnboardingAllPermissionsGranted() {
        var ctx = makeContext()
        let (phase, effects) = send(.allPermissionsGranted, phase: .onboardingPermissions, context: &ctx)
        XCTAssertEqual(phase, .onboardingTryHoldToType)
        XCTAssertTrue(effects.contains(.startHotkey))
    }

    func testOnboardingSetupDismissed() {
        var ctx = makeContext()
        let (phase, effects) = send(.setupDismissed, phase: .onboardingPermissions, context: &ctx)
        XCTAssertEqual(phase, .idle)
        XCTAssertTrue(effects.contains(.startHotkey))
    }

    // MARK: - Onboarding: Try Hold-to-Type

    func testTryHoldToTypeComplete() {
        var ctx = makeContext()
        let (phase, _) = send(.typingComplete, phase: .onboardingTryHoldToType, context: &ctx)
        XCTAssertEqual(phase, .onboardingTryTapToDispatch)
    }

    func testTryHoldToTypeDismissed() {
        var ctx = makeContext()
        let (phase, _) = send(.setupDismissed, phase: .onboardingTryHoldToType, context: &ctx)
        XCTAssertEqual(phase, .idle)
    }

    func testTryHoldToTypeKeyDown() {
        var ctx = makeContext()
        let (phase, effects) = send(.keyDown, phase: .onboardingTryHoldToType, context: &ctx)
        XCTAssertEqual(phase, .recording)
        XCTAssertTrue(effects.contains(.startRecording(.dictation)))
        XCTAssertTrue(effects.contains(.showOverlay(.waveform)))
    }

    // MARK: - Onboarding: Try Tap-to-Dispatch

    func testTryTapToDispatchComplete() {
        var ctx = makeContext()
        let (phase, _) = send(.dispatchComplete, phase: .onboardingTryTapToDispatch, context: &ctx)
        XCTAssertEqual(phase, .idle)
    }

    func testTryTapToDispatchDismissed() {
        var ctx = makeContext()
        let (phase, _) = send(.setupDismissed, phase: .onboardingTryTapToDispatch, context: &ctx)
        XCTAssertEqual(phase, .idle)
    }

    func testTryTapToDispatchKeyDown() {
        var ctx = makeContext()
        let (phase, effects) = send(.keyDown, phase: .onboardingTryTapToDispatch, context: &ctx)
        XCTAssertEqual(phase, .recording)
        XCTAssertTrue(effects.contains(.startRecording(.dictation)))
    }

    // MARK: - Idle → Recording

    func testIdleKeyDown() {
        var ctx = makeContext()
        let (phase, effects) = send(.keyDown, phase: .idle, context: &ctx)
        XCTAssertEqual(phase, .recording)
        XCTAssertTrue(effects.contains(.startRecording(.dictation)))
        XCTAssertTrue(effects.contains(.showOverlay(.waveform)))
        XCTAssertEqual(ctx.transcribedText, "")
        XCTAssertEqual(ctx.audioLevel, 0)
    }

    func testIdleKeyDownWhisper() {
        var ctx = makeContext(engine: .whisper)
        let (phase, effects) = send(.keyDown, phase: .idle, context: &ctx)
        XCTAssertEqual(phase, .recording)
        XCTAssertTrue(effects.contains(.startRecording(.whisper)))
    }

    // MARK: - Recording → Persistent / Finishing

    func testRecordingKeyUp() {
        var ctx = makeContext(transcribedText: "hello world")
        let (phase, effects) = send(.keyUp, phase: .recording, context: &ctx)
        XCTAssertEqual(phase, .transcribing)
        XCTAssertTrue(effects.contains(.stopRecording))
    }

    func testRecordingKeyCancel() {
        var ctx = makeContext(transcribedText: "some text")
        let (phase, effects) = send(.keyCancel, phase: .recording, context: &ctx)
        XCTAssertEqual(phase, .idle)
        XCTAssertTrue(effects.contains(.cancelRecording))
        XCTAssertTrue(effects.contains(.hideOverlay))
        XCTAssertEqual(ctx.transcribedText, "")
    }

    func testRecordingTranscriptionUpdated() {
        var ctx = makeContext()
        let (phase, _) = send(.transcriptionUpdated(text: "hello", audioLevel: 0.7), phase: .recording, context: &ctx)
        XCTAssertEqual(phase, .recording)
        XCTAssertEqual(ctx.transcribedText, "hello")
        XCTAssertEqual(ctx.audioLevel, 0.7)
    }

    // MARK: - Persistent

    func testPersistentKeyDown() {
        var ctx = makeContext(transcribedText: "test prompt")
        let (phase, effects) = send(.keyDown, phase: .persistent, context: &ctx)
        XCTAssertEqual(phase, .finishing(.dispatch))
        XCTAssertTrue(effects.contains(.stopRecording))
        XCTAssertTrue(effects.contains(.stopScreenCapture))
    }

    func testPersistentKeyCancel() {
        var ctx = makeContext(screenshotPaths: ["/tmp/a.png", "/tmp/b.png"])
        let (phase, effects) = send(.keyCancel, phase: .persistent, context: &ctx)
        XCTAssertEqual(phase, .idle)
        XCTAssertTrue(effects.contains(.cancelRecording))
        XCTAssertTrue(effects.contains(.deleteFiles(["/tmp/a.png", "/tmp/b.png"])))
        XCTAssertEqual(ctx.screenshotPaths, [])
    }

    func testPersistentTranscriptionUpdated() {
        var ctx = makeContext()
        let (phase, _) = send(.transcriptionUpdated(text: "partial", audioLevel: 0.3), phase: .persistent, context: &ctx)
        XCTAssertEqual(phase, .persistent)
        XCTAssertEqual(ctx.transcribedText, "partial")
    }

    func testPersistentContextCaptured() {
        var ctx = makeContext()
        let activeCtx = ActiveContext(appName: "Safari", windowTitle: "Google", url: "https://google.com")
        let (phase, _) = send(.contextCaptured(activeCtx), phase: .persistent, context: &ctx)
        XCTAssertEqual(phase, .persistent)
        XCTAssertEqual(ctx.capturedContext?.appName, "Safari")
        XCTAssertEqual(ctx.capturedContext?.url, "https://google.com")
    }

    func testPersistentScreenshotCaptured() {
        var ctx = makeContext()
        let (phase, _) = send(.screenshotCaptured(path: "/tmp/shot.png"), phase: .persistent, context: &ctx)
        XCTAssertEqual(phase, .persistent)
        XCTAssertEqual(ctx.screenshotPaths, ["/tmp/shot.png"])
    }

    func testPersistentSessionsRefreshed() {
        var ctx = makeContext()
        let sessions = [Session(id: "1", name: "Test", updatedAt: Date(), directory: "/tmp")]
        let (phase, _) = send(.sessionsRefreshed(sessions: sessions, projectDirectory: "/home"), phase: .persistent, context: &ctx)
        XCTAssertEqual(phase, .persistent)
        XCTAssertEqual(ctx.sessions.count, 1)
        XCTAssertEqual(ctx.currentProjectDirectory, "/home")
    }

    // MARK: - Finishing (Hold-to-Type)

    // MARK: - Transcribing → Hold-to-Type

    func testTranscribingWithText() {
        var ctx = makeContext()
        let (phase, effects) = send(.transcriptionFinished(text: "typed text"), phase: .transcribing, context: &ctx)
        XCTAssertEqual(phase, .idle)
        XCTAssertTrue(effects.contains(.typeText("typed text")))
        XCTAssertTrue(effects.contains(.hideOverlay))
    }

    func testTranscribingEmptyTextGoesToPersistent() {
        var ctx = makeContext()
        let (phase, effects) = send(.transcriptionFinished(text: ""), phase: .transcribing, context: &ctx)
        XCTAssertEqual(phase, .persistent)
        XCTAssertTrue(effects.contains(.startRecording(.dictation)))
    }

    func testTranscribingWithEnhancement() {
        var ctx = makeContext(enhancement: .appleIntelligence)
        let (phase, effects) = send(.transcriptionFinished(text: "raw text"), phase: .transcribing, context: &ctx)
        XCTAssertEqual(phase, .finishing(.holdToType))
        XCTAssertTrue(effects.contains(.enhanceText("raw text")))
        XCTAssertTrue(ctx.isEnhancing)
    }

    func testFinishingHoldToTypeEnhancementFinished() {
        var ctx = makeContext(enhancement: .appleIntelligence)
        ctx.isEnhancing = true
        let (phase, effects) = send(.enhancementFinished(text: "enhanced text"), phase: .finishing(.holdToType), context: &ctx)
        XCTAssertEqual(phase, .idle)
        XCTAssertTrue(effects.contains(.typeText("enhanced text")))
        XCTAssertTrue(effects.contains(.hideOverlay))
        XCTAssertFalse(ctx.isEnhancing)
    }

    // MARK: - Finishing (Dispatch)

    func testFinishingDispatchTranscriptionFinished() {
        var ctx = makeContext(server: testServer)
        ctx.capturedContext = ActiveContext(appName: "Code", windowTitle: "main.swift", url: nil, selectedText: "let x = 1")
        let (phase, effects) = send(.transcriptionFinished(text: "fix this"), phase: .finishing(.dispatch), context: &ctx)
        XCTAssertEqual(phase, .dispatching)
        XCTAssertTrue(effects.contains(.buildDestinations))
        XCTAssertTrue(effects.contains(.showOverlay(.picker)))
        XCTAssertFalse(ctx.currentPrompt.isEmpty)
    }

    func testFinishingDispatchEmptyText() {
        var ctx = makeContext(screenshotPaths: ["/tmp/shot.png"])
        let (phase, effects) = send(.transcriptionFinished(text: ""), phase: .finishing(.dispatch), context: &ctx)
        XCTAssertEqual(phase, .idle)
        XCTAssertTrue(effects.contains(.hideOverlay))
        XCTAssertTrue(effects.contains(.deleteFiles(["/tmp/shot.png"])))
    }

    func testFinishingDispatchWithEnhancement() {
        var ctx = makeContext(enhancement: .appleIntelligence, server: testServer)
        let (phase, effects) = send(.transcriptionFinished(text: "raw"), phase: .finishing(.dispatch), context: &ctx)
        XCTAssertEqual(phase, .finishing(.dispatch))
        XCTAssertTrue(effects.contains(.enhanceText("raw")))
        XCTAssertTrue(ctx.isEnhancing)
    }

    func testFinishingDispatchEnhancementFinished() {
        var ctx = makeContext(enhancement: .appleIntelligence, server: testServer)
        ctx.isEnhancing = true
        let (phase, effects) = send(.enhancementFinished(text: "enhanced"), phase: .finishing(.dispatch), context: &ctx)
        XCTAssertEqual(phase, .dispatching)
        XCTAssertFalse(ctx.isEnhancing)
        XCTAssertTrue(effects.contains(.buildDestinations))
        XCTAssertTrue(effects.contains(.showOverlay(.picker)))
    }

    // MARK: - Dispatching

    func testDispatchingDestinationPicked() {
        var ctx = makeContext(server: testServer, screenshotPaths: ["/tmp/a.png"])
        ctx.currentPrompt = "fix this bug"
        let dest = DispatchDestination.newOpenCodeWorkspace(displayDirectory: "~/proj", workingDirectory: "/Users/me/proj")
        let (phase, effects) = send(.destinationPicked(dest, editedPrompt: ""), phase: .dispatching, context: &ctx)
        XCTAssertEqual(phase, .idle)
        XCTAssertTrue(effects.contains(.hideOverlay))
        // Check dispatch effect
        let dispatchEffect = effects.first { if case .dispatch = $0 { return true } else { return false } }
        XCTAssertNotNil(dispatchEffect)
        if case .dispatch(let prompt, let server, _, let files, let workDir) = dispatchEffect! {
            XCTAssertEqual(prompt, "fix this bug")
            XCTAssertEqual(server, testServer)
            XCTAssertEqual(files, ["/tmp/a.png"])
            XCTAssertEqual(workDir, "/Users/me/proj")
        }
        XCTAssertEqual(ctx.screenshotPaths, [])
    }

    func testDispatchingDestinationPickedWithEditedPrompt() {
        var ctx = makeContext(server: testServer)
        ctx.currentPrompt = "original"
        let dest = DispatchDestination.newOpenCodeWorkspace(displayDirectory: "~/proj", workingDirectory: "/Users/me/proj")
        let (_, effects) = send(.destinationPicked(dest, editedPrompt: "edited prompt"), phase: .dispatching, context: &ctx)
        let dispatchEffect = effects.first { if case .dispatch = $0 { return true } else { return false } }
        if case .dispatch(let prompt, _, _, _, _) = dispatchEffect! {
            XCTAssertEqual(prompt, "edited prompt")
        }
    }

    func testDispatchingCancelled() {
        var ctx = makeContext(screenshotPaths: ["/tmp/a.png", "/tmp/b.png"])
        let (phase, effects) = send(.dispatchCancelled, phase: .dispatching, context: &ctx)
        XCTAssertEqual(phase, .idle)
        XCTAssertTrue(effects.contains(.hideOverlay))
        XCTAssertTrue(effects.contains(.deleteFiles(["/tmp/a.png", "/tmp/b.png"])))
        XCTAssertEqual(ctx.screenshotPaths, [])
    }

    // MARK: - Server discovery (any phase)

    func testServerDiscoveredFromAnyPhase() {
        var ctx = makeContext()
        let (phase, _) = send(.serverDiscovered(testServer), phase: .idle, context: &ctx)
        XCTAssertEqual(phase, .idle)
        XCTAssertEqual(ctx.server, testServer)
        XCTAssertTrue(ctx.openCodeConnected)
    }

    func testServerDisconnected() {
        var ctx = makeContext(server: testServer)
        let (_, _) = send(.serverDiscovered(nil), phase: .recording, context: &ctx)
        XCTAssertNil(ctx.server)
        XCTAssertFalse(ctx.openCodeConnected)
    }

    // MARK: - Full flow: hold-to-type

    func testFullHoldToTypeFlow() {
        var ctx = makeContext()
        // 1. Key down → recording
        let (p1, _) = send(.keyDown, phase: .idle, context: &ctx)
        XCTAssertEqual(p1, .recording)

        // 2. Transcription updates
        let (p2, _) = send(.transcriptionUpdated(text: "hello", audioLevel: 0.5), phase: p1, context: &ctx)
        XCTAssertEqual(p2, .recording)
        XCTAssertEqual(ctx.transcribedText, "hello")

        // 3. Key up → transcribing
        let (p3, _) = send(.keyUp, phase: p2, context: &ctx)
        XCTAssertEqual(p3, .transcribing)

        // 4. Transcription finished with text → idle + typeOrDispatch
        let (p4, effects) = send(.transcriptionFinished(text: "hello world"), phase: p3, context: &ctx)
        XCTAssertEqual(p4, .idle)
        XCTAssertTrue(effects.contains(.typeText("hello world")))
        XCTAssertTrue(effects.contains(.hideOverlay))
    }

    // MARK: - Full flow: tap-to-dispatch

    func testFullTapToDispatchFlow() {
        var ctx = makeContext(server: testServer)

        // 1. Key down → recording
        let (p1, _) = send(.keyDown, phase: .idle, context: &ctx)
        XCTAssertEqual(p1, .recording)

        // 2. Key up → transcribing
        let (p2, _) = send(.keyUp, phase: p1, context: &ctx)
        XCTAssertEqual(p2, .transcribing)

        // 3. Empty transcription → persistent (tap-to-dispatch mode)
        let (p3, _) = send(.transcriptionFinished(text: ""), phase: p2, context: &ctx)
        XCTAssertEqual(p3, .persistent)

        // 4. Transcription arrives while persistent
        let (p4, _) = send(.transcriptionUpdated(text: "fix the bug", audioLevel: 0.3), phase: p3, context: &ctx)
        XCTAssertEqual(p4, .persistent)

        // 5. Second key down → finishing dispatch
        let (p5, _) = send(.keyDown, phase: p4, context: &ctx)
        XCTAssertEqual(p5, .finishing(.dispatch))

        // 6. Transcription finished → dispatching
        let (p6, effects6) = send(.transcriptionFinished(text: "fix the bug"), phase: p5, context: &ctx)
        XCTAssertEqual(p6, .dispatching)
        XCTAssertTrue(effects6.contains(.buildDestinations))

        // 7. Destination picked → idle + dispatch
        let dest = DispatchDestination.newOpenCodeWorkspace(displayDirectory: "~/proj", workingDirectory: "/Users/me/proj")
        let (p7, effects7) = send(.destinationPicked(dest, editedPrompt: ""), phase: p6, context: &ctx)
        XCTAssertEqual(p7, .idle)
        XCTAssertTrue(effects7.contains(where: { if case .dispatch = $0 { return true } else { return false } }))
    }
}
