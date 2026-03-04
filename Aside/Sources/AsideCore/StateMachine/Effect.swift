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
    case startServerDiscovery
    case refreshSessions

    // Dispatch
    case dispatch(prompt: String, server: DiscoveredServer, sessionID: String?, files: [String], workingDir: String?)
    case buildDestinations

    // Overlay
    case showOverlay(OverlayEffect)
    case hideOverlay

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
