import AppKit
import SwiftUI
import Combine

// MARK: - Dispatch destination

/// A destination the user can pick from the dispatch picker.
struct DispatchDestination: Identifiable, Equatable {
    let id: String
    let label: String
    let detail: String?
    let time: String?
    let sessionID: String?

    static func newOpenCode() -> DispatchDestination {
        DispatchDestination(id: "opencode-new", label: "OpenCode", detail: "New session", time: nil, sessionID: nil)
    }

    static func openCodeSession(_ session: Session) -> DispatchDestination {
        DispatchDestination(id: "opencode-\(session.id)", label: session.name, detail: nil, time: session.timeString, sessionID: session.id)
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
    /// Editable prompt text shown in the dispatch picker.
    @Published var editablePrompt: String = ""

    /// Callback fired when user picks a destination.
    var onDestinationPicked: ((DispatchDestination, String) -> Void)?

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

    func showPicker(destinations: [DispatchDestination], prompt: String, onPicked: @escaping (DispatchDestination, String) -> Void) {
        self.destinations = destinations
        self.selectedIndex = 0
        self.editablePrompt = prompt
        self.onDestinationPicked = onPicked
        self.isPickingDestination = true
    }

    func moveSelection(by delta: Int) {
        guard !destinations.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + destinations.count) % destinations.count
    }

    func confirmSelection() {
        guard destinations.indices.contains(selectedIndex) else { return }
        onDestinationPicked?(destinations[selectedIndex], editablePrompt)
    }

    func reset() {
        isRecording = false
        audioLevel = 0
        transcribedText = ""
        isEnhancing = false
        isPickingDestination = false
        destinations = []
        selectedIndex = 0
        editablePrompt = ""
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
    /// Incremented on show, checked on hide completion to avoid stale orderOut.
    private var showGeneration: UInt64 = 0

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

    // Allow this panel to become key window for keyboard input
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show(state: OverlayState) {
        showGeneration &+= 1

        let content = OverlayContent(state: state)
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        contentView = hosting
        hostingView = hosting

        let size = CGSize(width: 360, height: 460)
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - size.width / 2
            let y = screen.visibleFrame.minY + 30
            setFrame(CGRect(origin: CGPoint(x: x, y: y), size: size), display: false)
        }

        ignoresMouseEvents = true
        alphaValue = 1
        orderFront(nil)
    }

    /// Enable keyboard interaction for the dispatch picker.
    /// The panel becomes key-accepting so the TextEditor can receive input.
    func enableKeyboardNavigation(state: OverlayState) {
        ignoresMouseEvents = false
        // Activate the app so this panel can become key and receive keyboard input
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak state] event in
            guard let state else { return event }

            // Enter: send to selected destination
            if event.keyCode == 36 {
                Task { @MainActor in state.confirmSelection() }
                return nil
            }

            // Escape: cancel
            if event.keyCode == 53 {
                Task { @MainActor in
                    state.onDestinationPicked?(DispatchDestination(id: "cancel", label: "", detail: nil, time: nil, sessionID: nil), "")
                }
                return nil
            }

            // Up/Down arrows: navigate session list
            if event.keyCode == 125 {
                Task { @MainActor in state.moveSelection(by: 1) }
                return nil
            }
            if event.keyCode == 126 {
                Task { @MainActor in state.moveSelection(by: -1) }
                return nil
            }

            return event // Pass through to TextEditor
        }
    }

    func hide(completion: (() -> Void)? = nil) {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        ignoresMouseEvents = true

        let gen = showGeneration
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.showGeneration == gen else { return }
            self.orderOut(nil)
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
        VStack(spacing: 8) {
            // Editable transcription
            TextEditor(text: $state.editablePrompt)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.08))
                )
                .frame(minHeight: 50, maxHeight: 100)
                .padding(.horizontal, 10)
                .padding(.top, 10)

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

            // Hints
            HStack(spacing: 12) {
                hintLabel("return", "↵ send")
                hintLabel("arrow.up.arrow.down", "navigate")
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
        .frame(maxWidth: 360)
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
            Image(systemName: "terminal")
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

            if let time = destination.time {
                Text(time)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .white.opacity(0.5) : .white.opacity(0.3))
                    .monospacedDigit()
            }

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
