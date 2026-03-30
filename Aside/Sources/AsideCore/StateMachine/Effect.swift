import Foundation

public enum Effect: Equatable, Sendable {
    // Recording
    case startRecording(TranscriptionEngine)
    case stopRecording
    case cancelRecording

    // Text delivery
    case typeText(String)
    case enhanceText(String)

    // Screen capture
    case startScreenCapture
    case stopScreenCapture

    // Context
    case captureContext

    // Permissions
    case checkPermissions
    case requestPermission(Permission)
case startPermissionPolling

    // Server
    case startDesktopServerDiscovery
    case refreshSessions

    // Dispatch
    case dispatch(prompt: String, server: DiscoveredServer, sessionID: String?, files: [String], workingDir: String?)
    case buildDestinations
    case startFinishingTimeout

    // Overlay
    case showOverlay(OverlayEffect)
    case hideOverlay

    // Safety net
    case copyToClipboard(String)
    case showDispatchFailure(prompt: String, reason: String)

    // Cleanup
    case deleteFiles([String])

    // History
    case addHistory(text: String, engine: TranscriptionEngine, enhanced: Bool)

    // Hotkey
    case startHotkey

    public enum OverlayEffect: Equatable, Sendable {
        case waveform
        case picker
    }
}
