import SwiftUI
import AsideCore

/// Interactive hold-to-type test — onboardingTryHoldToType phase.
struct TryHoldToTypeView: View {
    @ObservedObject var store: AppStore
    @FocusState private var isInputFocused: Bool
    @State private var typedText = ""
    @StateObject private var micMonitor = MicLevelMonitor()

    private var isRecording: Bool {
        store.phase == .recording || store.phase == .finishing(.holdToType)
    }

    /// Use store audio level during recording, mic monitor when idle
    private var currentAudioLevel: Float {
        isRecording ? store.context.audioLevel : micMonitor.audioLevel
    }

    var body: some View {
        VStack(spacing: 0) {
            WaveformBanner(audioLevel: currentAudioLevel, liveMode: true)
                .frame(height: 96)

            Spacer(minLength: 20)

            Text("Try Hold-to-Type")
                .font(.system(size: 20, weight: .semibold))
                .padding(.bottom, 6)

            Text("Hold the Right ⌥ key and speak. When you release, your words will appear below.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)

            // Keyboard illustration
            keyboardIllustration
                .padding(.bottom, 16)

            // Real editable text field — CGEvent typing goes here
            TextField("Your speech will appear here...", text: $typedText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .focused($isInputFocused)
                .frame(maxWidth: 320)
                .padding(.bottom, 20)

            Spacer(minLength: 24)
        }
        .frame(width: 420)
        .onAppear {
            isInputFocused = true
            micMonitor.start()
            autoAdvanceIfTextPresent()
        }
        .onDisappear {
            micMonitor.stop()
        }
        .onChange(of: store.phase) { _, newPhase in
            if newPhase == .onboardingTryHoldToType {
                autoAdvanceIfTextPresent()
            }
        }
    }

    private func autoAdvanceIfTextPresent() {
        guard !store.context.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if store.phase == .onboardingTryHoldToType {
                store.send(.typingComplete)
            }
        }
    }

    private var keyboardIllustration: some View {
        HStack(spacing: 3) {
            keyCap("", width: 120) // spacebar
            keyCap("⌘", width: 32)
            keyCap("⌥", width: 32, highlight: true)
            keyCap("◀", width: 32)
        }
    }

    private func keyCap(_ label: String, width: CGFloat, highlight: Bool = false) -> some View {
        Text(label)
            .font(.system(size: 10, weight: highlight ? .bold : .regular))
            .foregroundStyle(.white)
            .frame(width: width, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(highlight ? .blue.opacity(0.3) : .white.opacity(0.1))
            )
            .overlay(
                Group {
                    if highlight {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(.blue, lineWidth: 2)
                    }
                }
            )
    }
}
