import Foundation
import AsideCore

/// Wraps ContextCapture for async context capture.
final class ContextCaptureService {
    func capture() async -> ActiveContext {
        await Task.detached {
            ContextCapture.getActiveContext()
        }.value
    }
}
