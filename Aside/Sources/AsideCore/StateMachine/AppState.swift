import Foundation

// MARK: - AppPhase

public enum AppPhase: Equatable, Sendable {
    // Onboarding (3 screens, linear progression)
    case onboardingPermissions
    case onboardingTryHoldToType
    case onboardingTryTapToDispatch

    // Core app states
    case idle
    case recording           // key held, mic active
    case transcribing        // key released, waiting for transcription result to decide next step
    case persistent          // tap-to-dispatch: key released w/o text, still recording
    case finishing(FinishMode) // transcriber stopping
    case dispatching         // picker visible

    public enum FinishMode: Equatable, Sendable {
        case holdToType
        case dispatch
    }
}

// MARK: - AppEvent

public enum AppEvent: Equatable, Sendable {
    // Hotkey
    case keyDown
    case keyUp
    case keyCancel

    // Permissions
    case permissionsChecked(PermissionStatus)
    case permissionGranted(Permission)
    case allPermissionsGranted
    case setupDismissed

    // Onboarding
    case typingComplete
    case dispatchComplete

    // Transcription
    case transcriptionUpdated(text: String, audioLevel: Float)
    case transcriptionFinished(text: String)
    case enhancementFinished(text: String)

    // Server
    case desktopServerDiscovered(DiscoveredServer?)
    case sessionsRefreshed(sessions: [Session], projectDirectory: String?)

    // Context capture
    case contextCaptured(ActiveContext)
    case screenshotCaptured(path: String)

    // Dispatch
    case destinationPicked(DispatchDestination, editedPrompt: String)
    case dispatchCancelled
    case finishingTimeout

    // Screen capture
    case screenCaptureReady

    // Lifecycle
    case appLaunched
}

// MARK: - AppContext

public struct AppContext: Equatable, Sendable {
    // Permissions
    public var permissions: PermissionStatus

    // Server
    public var server: DiscoveredServer?         // OpenCode Desktop server (discovered via ps)
    public var sessions: [Session]
    public var currentProjectDirectory: String?

    // Recording
    public var transcribedText: String
    public var audioLevel: Float
    public var isEnhancing: Bool
    /// Text accumulated from recognizer auto-finishes during persistent recording (e.g. pauses, 60s limit)
    public var accumulatedTranscription: String


    // Capture
    public var capturedContext: ActiveContext?
    public var screenshotPaths: [String]

    // Dispatch
    public var currentPrompt: String
    public var destinations: [DispatchDestination]
    public var selectedDestinationIndex: Int

    // Preferences
    public var transcriptionEngine: TranscriptionEngine
    public var enhancementMode: EnhancementMode

    // Onboarding
    public var onboardingOrigin: AppPhase?

    // OpenCode connected
    public var openCodeConnected: Bool

    public init(
        permissions: PermissionStatus = PermissionStatus(),
        server: DiscoveredServer? = nil,
        sessions: [Session] = [],
        currentProjectDirectory: String? = nil,
        transcribedText: String = "",
        audioLevel: Float = 0,
        isEnhancing: Bool = false,
        accumulatedTranscription: String = "",
        capturedContext: ActiveContext? = nil,
        screenshotPaths: [String] = [],
        currentPrompt: String = "",
        destinations: [DispatchDestination] = [],
        selectedDestinationIndex: Int = 0,
        onboardingOrigin: AppPhase? = nil,
        transcriptionEngine: TranscriptionEngine = .dictation,
        enhancementMode: EnhancementMode = .off,
        openCodeConnected: Bool = false
    ) {
        self.permissions = permissions
        self.server = server
        self.sessions = sessions
        self.currentProjectDirectory = currentProjectDirectory
        self.transcribedText = transcribedText
        self.audioLevel = audioLevel
        self.isEnhancing = isEnhancing
        self.accumulatedTranscription = accumulatedTranscription
        self.capturedContext = capturedContext
        self.screenshotPaths = screenshotPaths
        self.currentPrompt = currentPrompt
        self.destinations = destinations
        self.selectedDestinationIndex = selectedDestinationIndex
        self.onboardingOrigin = onboardingOrigin
        self.transcriptionEngine = transcriptionEngine
        self.enhancementMode = enhancementMode
        self.openCodeConnected = openCodeConnected
    }
}
