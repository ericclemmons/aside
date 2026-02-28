import AppKit
import SwiftUI
import Combine

/// Observable state that drives the overlay UI. Either transcriber populates this.
@MainActor
class OverlayState: ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText = ""
    @Published var isEnhancing = false

    private var cancellables = Set<AnyCancellable>()

    /// Binds to a SpeechTranscriber's published properties.
    func bind(to transcriber: SpeechTranscriber) {
        cancellables.removeAll()
        transcriber.$isRecording.assign(to: &$isRecording)
        transcriber.$audioLevel.assign(to: &$audioLevel)
        transcriber.$transcribedText.assign(to: &$transcribedText)
        transcriber.$isEnhancing.assign(to: &$isEnhancing)
    }

    /// Binds to a WhisperTranscriber's published properties.
    func bind(to transcriber: WhisperTranscriber) {
        cancellables.removeAll()
        transcriber.$isRecording.assign(to: &$isRecording)
        transcriber.$audioLevel.assign(to: &$audioLevel)
        transcriber.$transcribedText.assign(to: &$transcribedText)
        transcriber.$isEnhancing.assign(to: &$isEnhancing)
    }

    func reset() {
        isRecording = false
        audioLevel = 0
        transcribedText = ""
        isEnhancing = false
        cancellables.removeAll()
    }
}

/// A borderless, non-activating floating panel that sits at the bottom-center
/// of the main screen and hosts the WaveformView.
class RecordingOverlayWindow: NSPanel {

    private var hostingView: NSHostingView<OverlayContent>?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true
    }

    func show(state: OverlayState) {
        let content = OverlayContent(state: state)
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        contentView = hosting
        hostingView = hosting

        // Position at bottom-center. The window is tall enough for the pill
        // to expand downward when text appears (top-center anchor in SwiftUI).
        let size = CGSize(width: 360, height: 140)
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - size.width / 2
            let y = screen.visibleFrame.minY + 30
            setFrame(CGRect(origin: CGPoint(x: x, y: y), size: size), display: false)
        }

        alphaValue = 1
        orderFront(nil)
    }

    func hide(completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            completion?()
        })
    }
}

// MARK: - SwiftUI content hosted inside the panel

private struct OverlayContent: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        WaveformView(
            audioLevel: state.audioLevel,
            isRecording: state.isRecording,
            transcribedText: state.transcribedText,
            isEnhancing: state.isEnhancing
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
    }
}
