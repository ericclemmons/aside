import Foundation

/// Pure function: (phase, context, event) → (newPhase, [Effect])
/// No side effects, no async, no I/O.
public func reduce(phase: AppPhase, context: inout AppContext, event: AppEvent) -> (AppPhase, [Effect]) {
    switch (phase, event) {

    // MARK: - App Lifecycle

    case (_, .appLaunched):
        return (phase, [.checkPermissions, .startServerDiscovery])

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
        return (.recording, [.startRecording(context.transcriptionEngine), .showOverlay(.waveform)])

    case (.onboardingTryTapToDispatch, .keyDown):
        context.transcribedText = ""
        context.audioLevel = 0
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
        let hasText = !context.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasText {
            return (.finishing(.holdToType), [.stopRecording])
        } else {
            return (.persistent, [.startScreenCapture, .captureContext, .refreshSessions])
        }

    case (.recording, .keyCancel):
        context.transcribedText = ""
        context.audioLevel = 0
        return (.idle, [.cancelRecording, .hideOverlay])

    case (.recording, .transcriptionUpdated(let text, let level)):
        context.transcribedText = text
        context.audioLevel = level
        return (.recording, [])

    // MARK: - Persistent (still recording after key released w/o text)

    case (.persistent, .keyDown):
        let hasText = !context.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasText {
            return (.finishing(.dispatch), [.stopRecording, .stopScreenCapture])
        } else {
            context.transcribedText = ""
            context.audioLevel = 0
            return (.idle, [.cancelRecording, .stopScreenCapture, .hideOverlay, .deleteFiles(context.screenshotPaths)])
        }

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

    case (.finishing(.holdToType), .transcriptionFinished(let text)):
        guard !text.isEmpty else {
            context.transcribedText = ""
            return (.idle, [.hideOverlay])
        }
        if context.enhancementMode == .appleIntelligence {
            context.isEnhancing = true
            return (.finishing(.holdToType), [.enhanceText(text), .addHistory(text: text, engine: context.transcriptionEngine, enhanced: false)])
        }
        context.transcribedText = ""
        return (.idle, [.typeText(text), .hideOverlay, .addHistory(text: text, engine: context.transcriptionEngine, enhanced: false)])

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
        context.server = server
        context.openCodeConnected = server != nil
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
