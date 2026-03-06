import SwiftUI

/// Canvas-based multi-layer sine wave animation.
/// Two sets of layers: filled gradient shapes and white glow stroke lines.
/// Used in both setup wizard and recording overlay.
struct WaveformBanner: View {
    var audioLevel: Float = 0
    /// false = always-on idle animation (welcome screen)
    /// true  = flat at silence, driven by mic (mic/speech screens)
    var liveMode: Bool = false
    /// Smaller blur radii and softer envelope for pill-sized canvases.
    var compact: Bool = false

    @State private var phase: Double = 0
    @State private var breathePhase: Double = 0
    @State private var smoothedLevel: Double = 0
    @State private var lineLevel: Double = 0
    @State private var animTimer: Timer?
    @State private var currentAudioLevel: Float = 0

    private let colorLayers: [(amp: Double, freq: Double, speed: Double, offset: Double, opacity: Double)] = [
        (0.70, 1.05, 0.60, 0.00,       0.55),
        (0.55, 1.80, 1.00, .pi * 0.65, 0.45),
        (0.80, 0.70, 0.40, .pi * 1.30, 0.35),
        (0.45, 2.50, 1.50, .pi * 0.35, 0.40),
    ]

    private let strokeLines: [(amp: Double, freq: Double, speed: Double, offset: Double, opacity: Double)] = [
        (0.88, 2.5, 1.10, .pi * 0.20, 0.72),
        (0.78, 3.8, 1.70, .pi * 1.10, 0.62),
        (0.92, 1.7, 0.75, .pi * 1.80, 0.55),
        (0.70, 4.8, 2.20, .pi * 0.90, 0.48),
        (0.82, 3.1, 1.40, .pi * 0.55, 0.58),
        (0.75, 5.5, 1.90, .pi * 1.45, 0.44),
        (0.85, 2.1, 0.95, .pi * 0.75, 0.50),
    ]

    private let gradient = Gradient(stops: [
        .init(color: Color(red: 0.55, green: 0.10, blue: 1.00), location: 0.00),
        .init(color: Color(red: 0.20, green: 0.35, blue: 1.00), location: 0.33),
        .init(color: Color(red: 0.00, green: 0.75, blue: 0.90), location: 0.66),
        .init(color: Color(red: 0.85, green: 0.15, blue: 0.85), location: 1.00),
    ])

    var body: some View {
        Canvas { context, size in
            let midY  = size.height / 2
            let halfH = midY * 0.88
            let steps = 220

            // Compact mode: center bulge, flatline at edges
            let gaussianSpread = compact ? 0.42 : 0.52
            let fillBlur: CGFloat  = compact ? 1.0 : 3.0
            let haloBlur: CGFloat  = compact ? 3.0 : 10.0
            let midBlur: CGFloat   = compact ? 1.0 : 4.0
            let haloWidth: CGFloat = compact ? 3.0 : 8.0
            let midWidth: CGFloat  = compact ? 1.5 : 3.0
            let fillOpacityScale   = compact ? 0.15 : 1.0

            let ampScale     = liveMode ? pow(smoothedLevel, 0.35) : 1.0 + smoothedLevel * 0.6
            let lineAmpScale = liveMode ? pow(lineLevel,     0.25) : 0.20 + lineLevel * 0.3

            for layer in colorLayers {
                var top = [CGPoint](), bot = [CGPoint]()
                for i in 0...steps {
                    let t        = Double(i) / Double(steps)
                    let x        = CGFloat(t) * size.width
                    let n        = (t - 0.5) * 4.8
                    let env = exp(-n * n * gaussianSpread)
                    let dy  = CGFloat(sin(t * .pi * 2 * layer.freq + phase * layer.speed + layer.offset)
                                      * layer.amp * min(env * ampScale, 1.0)) * halfH
                    top.append(CGPoint(x: x, y: midY - dy))
                    bot.append(CGPoint(x: x, y: midY + dy))
                }
                var path = Path()
                path.move(to: top[0])
                top.dropFirst().forEach { path.addLine(to: $0) }
                bot.reversed().forEach  { path.addLine(to: $0) }
                path.closeSubpath()
                var ctx = context
                ctx.opacity = layer.opacity * fillOpacityScale
                ctx.addFilter(.blur(radius: fillBlur))
                ctx.fill(path, with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: 0,          y: midY),
                    endPoint:   CGPoint(x: size.width, y: midY)
                ))
            }

            for (i, line) in strokeLines.enumerated() {
                let breathe = 0.5 + 0.5 * sin(breathePhase * line.speed * 1.8 + Double(i) * 2.1)
                let effectiveScale = lineAmpScale * (liveMode ? breathe : (0.5 + 0.5 * breathe))
                var path = Path()
                for j in 0...steps {
                    let t        = Double(j) / Double(steps)
                    let x        = CGFloat(t) * size.width
                    let n        = (t - 0.5) * 4.8
                    let env = exp(-n * n * gaussianSpread)
                    let y   = midY - CGFloat(sin(t * .pi * 2 * line.freq + phase * line.speed + line.offset)
                                             * line.amp * min(env * effectiveScale, 1.0)) * halfH
                    if j == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else       { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                // Line brightness scales with volume (dim at silence → full white at max)
                let volumeBrightness = liveMode ? (0.15 + 0.85 * lineLevel) : 1.0
                let haloOpacity = (compact ? line.opacity * 0.35 : line.opacity * 0.25) * volumeBrightness
                let midOpacity  = (compact ? line.opacity * 0.6  : line.opacity * 0.45) * volumeBrightness
                let coreOpacity = (compact ? line.opacity * 0.85 : line.opacity * 0.6)  * volumeBrightness
                var halo = context; halo.opacity = haloOpacity
                halo.addFilter(.blur(radius: haloBlur))
                halo.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: haloWidth, lineCap: .round))
                var mid = context; mid.opacity = midOpacity
                mid.addFilter(.blur(radius: midBlur))
                mid.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: midWidth, lineCap: .round))
                var core = context; core.opacity = coreOpacity
                core.addFilter(.blur(radius: 0.5))
                core.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { startAnimating() }
        .onDisappear { stopAnimating() }
        .onChange(of: audioLevel) { _, new in currentAudioLevel = new }
    }

    private func startAnimating() {
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in
                if compact {
                    // Slower, smoother animation for pill overlay
                    phase += 0.02 + smoothedLevel * 0.04
                    breathePhase += 0.08 + lineLevel * 0.12
                    let target = Double(currentAudioLevel)
                    if target > smoothedLevel {
                        smoothedLevel = smoothedLevel * 0.70 + target * 0.30
                    } else {
                        smoothedLevel = smoothedLevel * 0.92 + target * 0.08
                    }
                    if target > lineLevel {
                        lineLevel = lineLevel * 0.60 + target * 0.40
                    } else {
                        lineLevel = lineLevel * 0.88 + target * 0.12
                    }
                } else {
                    phase += 0.038 + smoothedLevel * 0.08
                    breathePhase += 0.19 + lineLevel * 0.30
                    let target = Double(currentAudioLevel)
                    if target > smoothedLevel {
                        smoothedLevel = smoothedLevel * 0.40 + target * 0.60
                    } else {
                        smoothedLevel = smoothedLevel * 0.76 + target * 0.24
                    }
                    if target > lineLevel {
                        lineLevel = lineLevel * 0.25 + target * 0.75
                    } else {
                        lineLevel = lineLevel * 0.64 + target * 0.36
                    }
                }
            }
        }
    }

    private func stopAnimating() { animTimer?.invalidate(); animTimer = nil }
}
