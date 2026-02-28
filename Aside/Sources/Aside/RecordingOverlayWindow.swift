import AppKit
import SwiftUI
import Combine

// MARK: - Dispatch destination

/// A destination the user can pick from the dispatch picker.
struct DispatchDestination: Identifiable, Equatable {
    let id: String
    let label: String
    let detail: String?
    let target: CLITarget
    let sessionID: String?

    static func newClaude() -> DispatchDestination {
        DispatchDestination(id: "claude-new", label: "Claude", detail: "New conversation", target: .claude, sessionID: nil)
    }

    static func newOpenCode() -> DispatchDestination {
        DispatchDestination(id: "opencode-new", label: "OpenCode", detail: "New session", target: .opencode, sessionID: nil)
    }

    static func openCodeSession(_ session: Session) -> DispatchDestination {
        DispatchDestination(id: "opencode-\(session.id)", label: session.name, detail: "OpenCode session", target: .opencode, sessionID: session.id)
    }
}

// MARK: - Overlay State

/// Observable state that drives the overlay UI.
@MainActor
class OverlayState: ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText = ""
    @Published var isEnhancing = false

    /// When true, shows the dispatch picker instead of the waveform.
    @Published var isPickingDestination = false
    @Published var destinations: [DispatchDestination] = []
    @Published var selectedIndex: Int = 0

    /// Callback fired when user picks a destination.
    var onDestinationPicked: ((DispatchDestination) -> Void)?

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

    func showPicker(destinations: [DispatchDestination], onPicked: @escaping (DispatchDestination) -> Void) {
        self.destinations = destinations
        self.selectedIndex = 0
        self.onDestinationPicked = onPicked
        self.isPickingDestination = true
    }

    func moveSelection(by delta: Int) {
        guard !destinations.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + destinations.count) % destinations.count
    }

    func confirmSelection() {
        guard destinations.indices.contains(selectedIndex) else { return }
        onDestinationPicked?(destinations[selectedIndex])
    }

    func reset() {
        isRecording = false
        audioLevel = 0
        transcribedText = ""
        isEnhancing = false
        isPickingDestination = false
        destinations = []
        selectedIndex = 0
        onDestinationPicked = nil
        cancellables.removeAll()
    }
}

// MARK: - Overlay Window

/// A borderless, non-activating floating panel that sits at the bottom-center
/// of the main screen and hosts either the WaveformView or DispatchPicker.
class RecordingOverlayWindow: NSPanel {

    private var hostingView: NSHostingView<OverlayContent>?
    private var keyMonitor: Any?

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

        let size = CGSize(width: 360, height: 300)
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - size.width / 2
            let y = screen.visibleFrame.minY + 30
            setFrame(CGRect(origin: CGPoint(x: x, y: y), size: size), display: false)
        }

        ignoresMouseEvents = true
        alphaValue = 1
        orderFront(nil)
    }

    /// Enable keyboard navigation for the dispatch picker.
    /// Uses a global CGEvent tap to intercept arrow/return/escape keys system-wide
    /// since NSPanel with nonactivatingPanel doesn't receive local key events.
    func enableKeyboardNavigation(state: OverlayState) {
        ignoresMouseEvents = false

        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak state] event in
            guard let state else { return }
            Task { @MainActor in
                switch event.keyCode {
                case 125: // Down arrow
                    state.moveSelection(by: 1)
                case 126: // Up arrow
                    state.moveSelection(by: -1)
                case 36: // Return
                    state.confirmSelection()
                case 53: // Escape
                    state.onDestinationPicked?(DispatchDestination(id: "cancel", label: "", detail: nil, target: .claude, sessionID: nil))
                default:
                    break
                }
            }
        }
    }

    func hide(completion: (() -> Void)? = nil) {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        ignoresMouseEvents = true

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
        VStack(spacing: 0) {
            if state.isPickingDestination {
                DispatchPickerView(state: state)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                WaveformView(
                    audioLevel: state.audioLevel,
                    isRecording: state.isRecording,
                    transcribedText: state.transcribedText,
                    isEnhancing: state.isEnhancing
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.isPickingDestination)
    }
}

// MARK: - Dispatch Picker View

private struct DispatchPickerView: View {
    @ObservedObject var state: OverlayState
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 6) {
            // Transcribed text preview
            if !state.transcribedText.isEmpty {
                Text(state.transcribedText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }

            // Destination list
            VStack(spacing: 2) {
                ForEach(Array(state.destinations.enumerated()), id: \.element.id) { index, dest in
                    DestinationRow(
                        destination: dest,
                        isSelected: index == state.selectedIndex
                    )
                    .onTapGesture {
                        state.selectedIndex = index
                        state.confirmSelection()
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)

            // Hint
            HStack(spacing: 12) {
                hintLabel("arrow.up.arrow.down", "navigate")
                hintLabel("return", "select")
                hintLabel("escape", "cancel")
            }
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
        )
        .frame(maxWidth: 320)
        .scaleEffect(appeared ? 1.0 : 0.9, anchor: .top)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }

    private func hintLabel(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 9))
        }
        .foregroundStyle(.white.opacity(0.35))
    }
}

private struct DestinationRow: View {
    let destination: DispatchDestination
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: destination.target == .claude ? "brain" : "terminal")
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(destination.label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.8))
                    .lineLimit(1)

                if let detail = destination.detail {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(isSelected ? .white.opacity(0.6) : .white.opacity(0.35))
                        .lineLimit(1)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? .white.opacity(0.12) : .clear)
        )
        .contentShape(Rectangle())
    }
}
