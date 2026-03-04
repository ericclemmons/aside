import AppKit
import SwiftUI
import Combine
import AsideCore

// MARK: - Overlay Mode

enum OverlayMode: Equatable {
    case hidden
    case waveform
    case picker
}

// MARK: - Overlay State

/// Observable state that drives the overlay UI.
@MainActor
class OverlayState: ObservableObject {
    @Published var mode: OverlayMode = .hidden
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText = ""
    @Published var isEnhancing = false

    @Published var destinations: [DispatchDestination] = []
    @Published var selectedIndex: Int = 0
    /// Editable prompt text shown in the dispatch picker.
    @Published var editablePrompt: String = ""
    /// Number of screenshots attached so far.
    @Published var screenshotCount: Int = 0

    /// Callback fired when user picks a destination.
    var onDestinationPicked: ((DispatchDestination, String) -> Void)?

    func moveSelection(by delta: Int) {
        guard !destinations.isEmpty else { return }
        guard destinations.contains(where: { $0.isSelectable }) else { return }

        var next = selectedIndex
        for _ in 0..<destinations.count {
            next = (next + delta + destinations.count) % destinations.count
            if destinations[next].isSelectable {
                selectedIndex = next
                return
            }
        }
    }

    func confirmSelection() {
        guard destinations.indices.contains(selectedIndex) else { return }
        guard destinations[selectedIndex].isSelectable else { return }
        onDestinationPicked?(destinations[selectedIndex], editablePrompt)
    }

    func reset() {
        mode = .hidden
        isRecording = false
        audioLevel = 0
        transcribedText = ""
        isEnhancing = false
        destinations = []
        selectedIndex = 0
        editablePrompt = ""
        screenshotCount = 0
    }
}

// MARK: - Overlay Window

/// A borderless, non-activating floating panel that sits at the bottom-center
/// of the main screen and hosts either the WaveformView or DispatchPicker.
class RecordingOverlayWindow: NSPanel {

    private var hostingView: NSHostingView<OverlayContent>?
    private var keyMonitor: Any?
    private var modeSink: AnyCancellable?

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

    /// Subscribe to state.mode and drive panel visibility reactively. Call once at launch.
    func observe(state: OverlayState) {
        // Create hosting view once
        let content = OverlayContent(state: state)
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        contentView = hosting
        hostingView = hosting

        // No receive(on:) — @MainActor OverlayState already publishes on main thread.
        // Synchronous delivery avoids races where monitor isn't installed yet.
        modeSink = state.$mode
            .sink { [weak self, weak state] mode in
                guard let self else { return }
                switch mode {
                case .hidden:
                    self.removeMonitors()
                    self.ignoresMouseEvents = true
                    self.orderOut(nil)

                case .waveform:
                    self.removeMonitors()
                    self.positionAtTop()
                    self.ignoresMouseEvents = true
                    self.alphaValue = 1
                    self.orderFront(nil)

                case .picker:
                    guard let state else { return }
                    self.positionAtTop()
                    self.ignoresMouseEvents = false
                    self.alphaValue = 1
                    NSApp.activate(ignoringOtherApps: true)
                    self.makeKeyAndOrderFront(nil)
                    self.installKeyMonitor(state: state)
                }
            }
    }

    /// Recalculate position: top-center of the screen containing the mouse cursor.
    private func positionAtTop() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let size = CGSize(width: 280, height: 460)
        let x = screen.visibleFrame.midX - size.width / 2
        let y = screen.visibleFrame.maxY - size.height
        setFrame(CGRect(origin: CGPoint(x: x, y: y), size: size), display: false)
    }

    // MARK: - Monitors

    private func installKeyMonitor(state: OverlayState) {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
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
                    state.onDestinationPicked?(
                        DispatchDestination(
                            id: "cancel",
                            kind: .sectionHeader,
                            label: "",
                            detail: nil,
                            time: nil,
                            sessionID: nil,
                            workingDirectory: nil
                        ),
                        ""
                    )
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

    private func removeMonitors() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}

// MARK: - SwiftUI content hosted inside the panel

private struct OverlayContent: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        VStack(spacing: 0) {
            switch state.mode {
            case .hidden:
                EmptyView()
            case .waveform:
                WaveformView(
                    audioLevel: state.audioLevel,
                    isRecording: state.isRecording,
                    transcribedText: state.transcribedText,
                    isEnhancing: state.isEnhancing
                )
            case .picker:
                DispatchPickerView(state: state)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.mode)
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
                .mask(
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 16)
                    }
                )
                .padding(.horizontal, 10)
                .padding(.top, 10)

            // Screenshot count badge
            if state.screenshotCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 10, weight: .medium))
                    Text("\(state.screenshotCount) screenshot\(state.screenshotCount == 1 ? "" : "s") attached")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Destination list
            VStack(spacing: 2) {
                ForEach(Array(state.destinations.enumerated()), id: \.element.id) { index, dest in
                    DestinationRow(
                        destination: dest,
                        isSelected: dest.isSelectable && index == state.selectedIndex
                    )
                    .onTapGesture {
                        guard dest.isSelectable else { return }
                        state.selectedIndex = index
                        state.confirmSelection()
                    }
                }
            }
            .padding(.horizontal, 6)

            // Hints
            HStack(spacing: 12) {
                hintLabel("return", "send")
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
        if destination.kind == .sectionHeader {
            Text(destination.label)
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 3)
        } else {
        HStack(spacing: 8) {
            Group {
                if let url = Bundle.module.url(forResource: "opencode.logo", withExtension: "svg"),
                   let img = NSImage(contentsOf: url) {
                    Image(nsImage: img)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 11))
                }
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
            .frame(width: 13, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(destination.label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.8))
                    .lineLimit(1)

                if let detail = destination.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(isSelected ? 0.45 : 0.3))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 6)

            if let time = destination.time {
                Text(time)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .white.opacity(0.5) : .white.opacity(0.3))
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
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
}
