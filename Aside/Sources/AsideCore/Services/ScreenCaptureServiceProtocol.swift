import Foundation

@MainActor
public protocol ScreenCaptureServiceProtocol {
    func startCapture() async -> [String]
    func stopCapture()
    func deleteFiles(_ paths: [String])
}
