import Foundation

/// Pure function: (phase, context, event) → (newPhase, [Effect])
/// No side effects, no async, no I/O.
public func reduce(phase: AppPhase, context: inout AppContext, event: AppEvent) -> (AppPhase, [Effect]) {
    switch (phase, event) {

    // MARK: - App Lifecycle

    case (_, .appLaunched):
        return (phase, [.checkPermissions, .startAsideServer, .startDesktopServerDiscovery, .startPermissionPolling])

    // MARK: - Onboarding: Permissions

    case (.onboardingPermissions, .permissionsChecked(let status)):
        context.permissions = status
        return (.onboardingPermissions, [])

    case (.onboardingPermissions, .permissionGranted(let perm)):
        context.permissions[perm] = true
        return (.onboardingPermissions, [.checkPermissions])

    case (.onboardingPermissions, .allPermissionsGranted):
        return (.onboardingTryHoldToType, [.startHotkey])

    case (.onboardingPermissions, .setupDismissed):
        return (.idle, [.startHotkey])

    // MARK: - Onboarding: Try Hold-to-Type

    case (.onboardingTryHoldToType, .typingComplete):
        return (.onboardingTryTapToDispatch, [])

    case (.onboardingTryHoldToType, .setupDismissed):
        return (.idle, [])

    // Allow recording during onboarding try steps
    case (.onboardingTryHoldToType, .keyDown):
        context.transcribedText = ""
        context.audioLevel = 0

        context.onboardingOrigin = .onboardingTryHoldToType
        return (.recording, [.startRecording(context.transcriptionEngine), .showOverlay(.waveform)])

    case (.onboardingTryTapToDispatch, .keyDown):
        context.transcribedText = ""
        context.audioLevel = 0

        context.onboardingOrigin = .onboardingTryTapToDispatch
        return (.recording, [.startRecording(context.transcriptionEngine), .showOverlay(.waveform)])

    // MARK: - Onboarding: Try Tap-to-Dispatch

    case (.onboardingTryTapToDispatch, .dispatchComplete):
        return (.idle, [])

    case (.onboardingTryTapToDispatch, .setupDismissed):
        return (.idle, [])

    // MARK: - Idle → Recording

    case (.idle, .keyDown):
        context.transcribedText = ""
        context.audioLevel = 0
        context.isEnhancing = false
        context.capturedContext = nil
        context.screenshotPaths = []

        return (.recording, [.startRecording(context.transcriptionEngine), .showOverlay(.waveform)])

    // MARK: - Recording

    case (.recording, .keyUp):
        // Stop recording → transcribing; transcriptionFinished decides hold-to-type vs persistent
        return (.transcribing, [.stopRecording])

    case (.recording, .keyCancel):
        context.transcribedText = ""
        context.audioLevel = 0
        if let origin = context.onboardingOrigin {
            context.onboardingOrigin = nil
            return (origin, [.cancelRecording, .hideOverlay])
        }
        return (.idle, [.cancelRecording, .hideOverlay])

    case (.recording, .transcriptionUpdated(let text, let level)):
        context.transcribedText = text
        context.audioLevel = level
        return (.recording, [])

    // MARK: - Transcribing (key released, waiting for transcription result)

    case (.transcribing, .transcriptionFinished(let text)):
        // Onboarding: type the text, return to onboarding phase
        if let origin = context.onboardingOrigin {
            context.onboardingOrigin = nil
            if text.isEmpty {
                context.transcribedText = ""
                return (origin, [.hideOverlay])
            }
            context.transcribedText = text
            return (origin, [.typeText(text), .hideOverlay])
        }
        guard !text.isEmpty else {
            // No text → tap-to-dispatch: restart recording, keep overlay, capture context
            return (.persistent, [.startRecording(context.transcriptionEngine), .startScreenCapture, .captureContext, .refreshSessions])
        }
        // Has text → hold-to-type
        if context.enhancementMode == .appleIntelligence {
            context.isEnhancing = true
            return (.finishing(.holdToType), [.enhanceText(text), .addHistory(text: text, engine: context.transcriptionEngine, enhanced: false)])
        }
        context.transcribedText = ""
        return (.idle, [.typeText(text), .hideOverlay, .addHistory(text: text, engine: context.transcriptionEngine, enhanced: false)])

    case (.transcribing, .keyCancel):
        context.transcribedText = ""
        context.audioLevel = 0
        if let origin = context.onboardingOrigin {
            context.onboardingOrigin = nil
            return (origin, [.cancelRecording, .hideOverlay])
        }
        return (.idle, [.cancelRecording, .hideOverlay])

    // MARK: - Persistent (still recording after key released w/o text)

    case (.persistent, .keyDown):
        // Stop recording and wait for transcriptionFinished (handles both streaming and batch engines)
        return (.finishing(.dispatch), [.stopRecording, .stopScreenCapture])

    case (.persistent, .keyCancel):
        let paths = context.screenshotPaths
        context.transcribedText = ""
        context.audioLevel = 0
        context.screenshotPaths = []
        return (.idle, [.cancelRecording, .stopScreenCapture, .hideOverlay, .deleteFiles(paths)])

    case (.persistent, .transcriptionUpdated(let text, let level)):
        context.transcribedText = text
        context.audioLevel = level
        return (.persistent, [])

    case (.persistent, .contextCaptured(let ctx)):
        context.capturedContext = ctx
        return (.persistent, [])

    case (.persistent, .screenshotCaptured(let path)):
        context.screenshotPaths.append(path)
        return (.persistent, [])

    case (.persistent, .sessionsRefreshed(let sessions, let projectDir)):
        context.sessions = sessions
        context.currentProjectDirectory = projectDir
        return (.persistent, [])

    // MARK: - Finishing

    // finishing(.holdToType) is only reached from transcribing when enhancement is active
    case (.finishing(.holdToType), .enhancementFinished(let text)):
        context.isEnhancing = false
        context.transcribedText = ""
        return (.idle, [.typeText(text), .hideOverlay])

    case (.finishing(.dispatch), .transcriptionFinished(let text)):
        guard !text.isEmpty else {
            let paths = context.screenshotPaths
            context.transcribedText = ""
            context.screenshotPaths = []
            return (.idle, [.hideOverlay, .deleteFiles(paths)])
        }
        if context.enhancementMode == .appleIntelligence {
            context.isEnhancing = true
            return (.finishing(.dispatch), [.enhanceText(text)])
        }
        let prompt = PromptBuilder.buildPrompt(transcription: text, context: context.capturedContext)
        context.currentPrompt = prompt
        return (.dispatching, [.buildDestinations, .showOverlay(.picker), .addHistory(text: text, engine: context.transcriptionEngine, enhanced: false)])

    case (.finishing(.dispatch), .enhancementFinished(let text)):
        context.isEnhancing = false
        let prompt = PromptBuilder.buildPrompt(transcription: text, context: context.capturedContext)
        context.currentPrompt = prompt
        return (.dispatching, [.buildDestinations, .showOverlay(.picker), .addHistory(text: text, engine: context.transcriptionEngine, enhanced: true)])

    // MARK: - Dispatching (picker visible)

    case (.dispatching, .destinationPicked(let dest, let editedPrompt)):
        guard let server = context.server else {
            return (.idle, [.hideOverlay])
        }
        let prompt = editedPrompt.isEmpty ? context.currentPrompt : editedPrompt
        let paths = context.screenshotPaths
        context.screenshotPaths = []
        context.transcribedText = ""
        context.currentPrompt = ""
        context.destinations = []
        context.capturedContext = nil
        return (.idle, [
            .dispatch(prompt: prompt, server: server, sessionID: dest.sessionID, files: paths, workingDir: dest.workingDirectory),
            .hideOverlay
        ])

    case (.dispatching, .keyDown):
        // Right Option tap dismisses picker (same as Escape)
        let paths = context.screenshotPaths
        context.screenshotPaths = []
        context.transcribedText = ""
        context.currentPrompt = ""
        context.destinations = []
        context.capturedContext = nil
        return (.idle, [.hideOverlay, .deleteFiles(paths)])

    case (.dispatching, .dispatchCancelled):
        let paths = context.screenshotPaths
        context.screenshotPaths = []
        context.transcribedText = ""
        context.currentPrompt = ""
        context.destinations = []
        context.capturedContext = nil
        return (.idle, [.hideOverlay, .deleteFiles(paths)])

    // MARK: - Server discovery (any phase)

    case (_, .serverDiscovered(let server)):
        context.asideServer = server
        // Update active server based on selection
        if context.selectedServerTarget == .aside {
            context.server = server
        }
        context.openCodeConnected = context.server != nil
        return (phase, [])

    case (_, .desktopServerDiscovered(let server)):
        context.desktopServer = server
        if context.selectedServerTarget == .desktop {
            context.server = server
        }
        context.openCodeConnected = context.server != nil
        return (phase, [])

    case (_, .serverTargetChanged(let target)):
        context.selectedServerTarget = target
        switch target {
        case .aside: context.server = context.asideServer
        case .desktop: context.server = context.desktopServer
        }
        context.openCodeConnected = context.server != nil
        return (phase, [])

    case (_, .sessionsRefreshed(let sessions, let projectDir)):
        context.sessions = sessions
        context.currentProjectDirectory = projectDir
        return (phase, [])

    case (_, .permissionsChecked(let status)):
        context.permissions = status
        if status.allGranted && phase == .onboardingPermissions {
            // Don't auto-advance, user clicks "Get Started"
        }
        return (phase, [])

    // MARK: - Default (ignore unhandled events)

    default:
        return (phase, [])
    }
}
