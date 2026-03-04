import SwiftUI

struct WaveformView: View {
    var audioLevel: Float
    var isRecording: Bool
    var transcribedText: String
    var isEnhancing: Bool = false

    // Processing bars state
    private let barCount = 16
    @State private var barPhases: [Double] = (0..<16).map { Double($0) * 0.4 }
    @State private var spinAngle: Double = 0
    @State private var animTimer: Timer?

    @State private var appeared = false
    @State private var textScrollID = UUID()

    private var hasText: Bool { !transcribedText.isEmpty && !isEnhancing }
    private var textOverflows: Bool { transcribedText.count > 38 }
    private var cornerRadius: CGFloat { hasText ? 16 : 20 }

    var body: some View {
        VStack(spacing: 0) {
            if isEnhancing {
                enhancingRow
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                WaveformBanner(audioLevel: audioLevel, liveMode: true)
                    .frame(height: 96)

                if hasText {
                    transcriptionText
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.black)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(.spring(response: 0.4, dampingFraction: 0.55, blendDuration: 0.1), value: hasText)
        .animation(.easeInOut(duration: 0.25), value: isEnhancing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .offset(y: appeared ? 0 : -20)
        .scaleEffect(appeared ? 1.0 : 0.8, anchor: .top)
        .opacity(appeared ? 1.0 : 0.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: appeared)
        .onAppear {
            startAnimating()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { appeared = true }
        }
        .onDisappear {
            stopAnimating()
            appeared = false
        }
    }

    // MARK: - Enhancing row (spinner + shimmer bars)

    private var enhancingRow: some View {
        HStack(spacing: 10) {
            processingSpinner
            processingBars
        }
    }

    private var processingSpinner: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(spinAngle))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    spinAngle = 360
                }
            }
    }

    private var processingBars: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white.opacity(processingBarOpacity(for: index)))
                    .frame(width: 2.5, height: processingBarHeight(for: index))
            }
        }
        .frame(height: 24)
    }

    private func processingBarHeight(for index: Int) -> CGFloat {
        let sine = (sin(barPhases[index]) + 1) / 2
        return 6 + 4 * CGFloat(sine)
    }

    private func processingBarOpacity(for index: Int) -> Double {
        let sine = (sin(barPhases[index] * 1.2) + 1) / 2
        return 0.35 + 0.4 * sine
    }

    // MARK: - Transcription text

    private var transcriptionText: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    Text(transcribedText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .id(textScrollID)
                    Spacer().frame(width: 4)
                }
            }
            .mask(
                HStack(spacing: 0) {
                    if textOverflows {
                        LinearGradient(colors: [.clear, .white], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 16)
                            .transition(.opacity)
                    }
                    Color.white
                }
            )
            .onChange(of: transcribedText) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(textScrollID, anchor: .trailing)
                }
            }
        }
        .transition(.opacity)
    }

    // MARK: - Animation timer (processing bars only — WaveformBanner has its own)

    private func startAnimating() {
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in
                let speed: Double = isEnhancing ? 0.08 : 0.05
                for i in 0..<barCount {
                    barPhases[i] += speed + Double(i) * 0.008
                }
            }
        }
    }

    private func stopAnimating() {
        animTimer?.invalidate()
        animTimer = nil
    }
}
