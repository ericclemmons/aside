import SwiftUI
import AsideCore

/// Interactive tap-to-dispatch test — onboardingTryTapToDispatch phase.
struct TryTapToDispatchView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            WaveformBanner(audioLevel: store.context.audioLevel, liveMode: true)
                .frame(height: 96)

            Spacer(minLength: 20)

            Text("Try Tap-to-Dispatch")
                .font(.system(size: 20, weight: .semibold))
                .padding(.bottom, 6)

            Text("Tap Right ⌥ to start recording, speak your prompt, then tap again to stop. Pick a destination to dispatch.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)

            // Numbered steps
            VStack(alignment: .leading, spacing: 12) {
                stepRow(1, "Tap Right ⌥ to start recording")
                stepRow(2, "Speak your prompt")
                stepRow(3, "Tap Right ⌥ again to stop")
                stepRow(4, "Pick a destination and press Enter")
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 20)

            HStack(spacing: 12) {
                Button(action: { store.send(.setupDismissed) }) {
                    Text("Finish Setup")
                        .font(.system(size: 13, weight: .medium))
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 24)
        }
        .frame(width: 420)
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(.blue))

            Text(text)
                .font(.system(size: 13))
        }
    }
}
