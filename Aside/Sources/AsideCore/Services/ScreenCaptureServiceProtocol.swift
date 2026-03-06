import Foundation

@MainActor
public protocol ScreenCaptureServiceProtocol {
    func startCapture(onCapture: @escaping (String) -> Void)
    func stopCapture()
    func deleteFiles(_ paths: [String])
}
