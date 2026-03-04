import AppKit
import SwiftUI
import Combine
import AsideCore

/// Window controller for the setup wizard. Switches views based on store.phase.
@MainActor
class StoreSetupWindowController {
    private var windowController: NSWindowController?
    private var phaseSink: AnyCancellable?

    func show(store: AppStore, permissionService: PermissionService) {
        // Check if all permissions already granted
        let status = permissionService.checkAll()
        store.send(.permissionsChecked(status))
        if status.allGranted {
            // Skip setup, go straight to idle
            store.send(.setupDismissed)
            return
        }

        let rootView = StoreSetupRootView(store: store, permissionService: permissionService)
            .environment(\.colorScheme, .dark)
            .preferredColorScheme(.dark)
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.appearance = NSAppearance(named: .darkAqua)

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentViewController = hostingController
        window.contentView?.appearance = NSAppearance(named: .darkAqua)
        window.setContentSize(NSSize(width: 420, height: 500))
        window.title = "Aside"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller

        // Close window when leaving onboarding
        phaseSink = store.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                switch phase {
                case .onboardingPermissions, .onboardingTryHoldToType, .onboardingTryTapToDispatch:
                    break // keep open
                default:
                    self?.close()
                }
            }

        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }

    func close() {
        phaseSink = nil
        windowController?.window?.close()
        windowController = nil
    }
}

/// Root view that switches content based on store.phase.
private struct StoreSetupRootView: View {
    @ObservedObject var store: AppStore
    let permissionService: PermissionService

    var body: some View {
        Group {
            switch store.phase {
            case .onboardingPermissions:
                SetupView(store: store, permissionService: permissionService)
            case .onboardingTryHoldToType:
                TryHoldToTypeView(store: store)
            case .onboardingTryTapToDispatch:
                TryTapToDispatchView(store: store)
            default:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.phase)
    }
}
