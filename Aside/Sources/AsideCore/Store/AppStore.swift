import Foundation
import Combine

@MainActor
public final class AppStore: ObservableObject {
    @Published public private(set) var phase: AppPhase
    @Published public private(set) var context: AppContext

    public var effectHandler: ((Effect, @escaping (AppEvent) -> Void) -> Void)?

    public init(phase: AppPhase = .onboardingPermissions, context: AppContext = AppContext()) {
        self.phase = phase
        self.context = context
    }

    public func send(_ event: AppEvent) {
        let (newPhase, effects) = reduce(phase: phase, context: &context, event: event)
        phase = newPhase

        for effect in effects {
            effectHandler?(effect) { [weak self] event in
                self?.send(event)
            }
        }
    }

    /// Direct context mutation for effects that need to update UI-layer data (e.g. destinations).
    public func updateContext(_ mutate: (inout AppContext) -> Void) {
        mutate(&context)
    }
}
