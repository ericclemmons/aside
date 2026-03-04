import Foundation

public enum Permission: String, CaseIterable, Equatable, Sendable {
    case screenRecording
    case microphone
    case speechRecognition
    case accessibility
}

public struct PermissionStatus: Equatable, Sendable {
    public var screenRecording: Bool
    public var microphone: Bool
    public var speechRecognition: Bool
    public var accessibility: Bool

    public init(screenRecording: Bool = false, microphone: Bool = false, speechRecognition: Bool = false, accessibility: Bool = false) {
        self.screenRecording = screenRecording
        self.microphone = microphone
        self.speechRecognition = speechRecognition
        self.accessibility = accessibility
    }

    public var allGranted: Bool {
        screenRecording && microphone && speechRecognition && accessibility
    }

    public subscript(permission: Permission) -> Bool {
        get {
            switch permission {
            case .screenRecording: return screenRecording
            case .microphone: return microphone
            case .speechRecognition: return speechRecognition
            case .accessibility: return accessibility
            }
        }
        set {
            switch permission {
            case .screenRecording: screenRecording = newValue
            case .microphone: microphone = newValue
            case .speechRecognition: speechRecognition = newValue
            case .accessibility: accessibility = newValue
            }
        }
    }
}

@MainActor
public protocol PermissionServiceProtocol {
    func checkAll() -> PermissionStatus
    func request(_ permission: Permission) async -> Bool
    func openSystemPreferences(for permission: Permission)
}
