import Foundation
import AsideCore

/// Wraps HotkeyManager and maps callbacks to AppEvents.
@MainActor
final class HotkeyService {
    private let hotkeyManager = HotkeyManager()

    var isRunning: Bool { hotkeyManager.isRunning }

    func start(send: @escaping (AppEvent) -> Void) {
        hotkeyManager.mode = .holdToTalk
        hotkeyManager.onKeyDown = { send(.keyDown) }
        hotkeyManager.onKeyUp = { send(.keyUp) }
        hotkeyManager.onCancel = { send(.keyCancel) }
        hotkeyManager.start()
    }

    func stop() {
        hotkeyManager.stop()
    }

    func resetToggle() {
        hotkeyManager.resetToggle()
    }
}
