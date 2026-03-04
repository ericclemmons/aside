import SwiftUI
import AsideCore

/// Interactive hold-to-type test — onboardingTryHoldToType phase.
struct TryHoldToTypeView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            WaveformBanner(audioLevel: store.context.audioLevel, liveMode: true)
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

            // Text field showing transcription
            VStack(spacing: 8) {
                TextField("Your speech will appear here...", text: .constant(store.context.transcribedText))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .disabled(true)
                    .frame(maxWidth: 320)

                if !store.context.transcribedText.isEmpty {
                    Text("It worked! Your speech was typed.")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                }
            }
            .padding(.bottom, 20)

            HStack(spacing: 12) {
                if !store.context.transcribedText.isEmpty {
                    Button(action: { store.send(.typingComplete) }) {
                        Text("Continue")
                            .font(.system(size: 13, weight: .medium))
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }

                Button(action: { store.send(.setupDismissed) }) {
                    Text("Skip")
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.bottom, 24)
        }
        .frame(width: 420)
    }

    private var keyboardIllustration: some View {
        HStack(spacing: 4) {
            ForEach(["ctrl", "alt", "cmd", "space", "cmd"], id: \.self) { key in
                keyCap(key, highlight: key == "alt")
            }
            keyCap("alt", highlight: true)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.blue, lineWidth: 2)
                )
        }
    }

    private func keyCap(_ label: String, highlight: Bool = false) -> some View {
        Text(label)
            .font(.system(size: 9, weight: highlight ? .bold : .regular))
            .foregroundStyle(highlight ? .white : .secondary)
            .padding(.horizontal, label == "space" ? 24 : 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(highlight ? .blue.opacity(0.3) : .white.opacity(0.08))
            )
    }
}
