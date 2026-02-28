#!/usr/bin/env swift
// Generates Aside app icon: dark rounded-rect with a gradient waveform symbol
import AppKit
import Foundation

let size = 1024
let cgSize = CGSize(width: size, height: size)

// Create bitmap context
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Failed to create context")
}

let s = CGFloat(size)

// --- Background: dark rounded rect with subtle gradient ---
let cornerRadius: CGFloat = s * 0.22 // macOS icon corner radius
let rect = CGRect(x: 0, y: 0, width: s, height: s)
let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()

// Dark gradient background (charcoal to near-black)
let bgColors = [
    CGColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1.0),
    CGColor(red: 0.06, green: 0.06, blue: 0.10, alpha: 1.0),
] as CFArray
let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0])!
ctx.drawLinearGradient(bgGradient, start: CGPoint(x: s/2, y: s), end: CGPoint(x: s/2, y: 0), options: [])
ctx.restoreGState()

// --- Draw waveform bars with gradient ---
let barCount = 9
let barWidth: CGFloat = s * 0.045
let barSpacing: CGFloat = s * 0.025
let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
let startX = (s - totalWidth) / 2
let centerY = s * 0.50

// Bar heights as ratios of max (gives a waveform shape)
let barHeights: [CGFloat] = [0.18, 0.35, 0.55, 0.80, 1.0, 0.80, 0.55, 0.35, 0.18]
let maxBarHeight: CGFloat = s * 0.38

// Gradient colors for bars (cyan → purple → pink)
let barGradientColors = [
    CGColor(red: 0.30, green: 0.85, blue: 0.95, alpha: 1.0),  // cyan
    CGColor(red: 0.55, green: 0.40, blue: 0.95, alpha: 1.0),  // purple
    CGColor(red: 0.95, green: 0.40, blue: 0.65, alpha: 1.0),  // pink
] as CFArray
let barGradient = CGGradient(colorsSpace: colorSpace, colors: barGradientColors, locations: [0.0, 0.5, 1.0])!

for i in 0..<barCount {
    let x = startX + CGFloat(i) * (barWidth + barSpacing)
    let h = maxBarHeight * barHeights[i]
    let barRect = CGRect(x: x, y: centerY - h/2, width: barWidth, height: h)
    let barPath = CGPath(roundedRect: barRect, cornerWidth: barWidth/2, cornerHeight: barWidth/2, transform: nil)

    ctx.saveGState()
    ctx.addPath(barPath)
    ctx.clip()
    // Gradient runs left-to-right across the full waveform
    ctx.drawLinearGradient(barGradient,
        start: CGPoint(x: startX, y: centerY),
        end: CGPoint(x: startX + totalWidth, y: centerY),
        options: [])
    ctx.restoreGState()
}

// --- Add subtle glow behind bars ---
// Draw again with lower opacity and blur effect (approximate with larger bars)
ctx.saveGState()
ctx.setAlpha(0.3)
for i in 0..<barCount {
    let x = startX + CGFloat(i) * (barWidth + barSpacing) - 4
    let h = maxBarHeight * barHeights[i] + 16
    let barRect = CGRect(x: x, y: centerY - h/2, width: barWidth + 8, height: h)
    let barPath = CGPath(roundedRect: barRect, cornerWidth: (barWidth + 8)/2, cornerHeight: (barWidth + 8)/2, transform: nil)

    ctx.addPath(barPath)
    ctx.clip()
    ctx.drawLinearGradient(barGradient,
        start: CGPoint(x: startX, y: centerY),
        end: CGPoint(x: startX + totalWidth, y: centerY),
        options: [])
    ctx.resetClip()
}
ctx.restoreGState()

// --- Generate image ---
guard let cgImage = ctx.makeImage() else {
    fatalError("Failed to create image")
}

let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
guard let tiff = nsImage.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to create PNG")
}

let outputDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let pngPath = outputDir.appendingPathComponent("icon_1024.png")
try png.write(to: pngPath)
print("Written: \(pngPath.path)")

// --- Generate iconset and icns ---
let iconsetDir = outputDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let iconSizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (px, name) in iconSizes {
    let dest = iconsetDir.appendingPathComponent(name)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-z", "\(px)", "\(px)", pngPath.path, "--out", dest.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
}

// Convert iconset to icns
let icnsPath = outputDir.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsPath.path]
try iconutil.run()
iconutil.waitUntilExit()

print("Written: \(icnsPath.path)")

// Cleanup
try? FileManager.default.removeItem(at: iconsetDir)
try? FileManager.default.removeItem(at: pngPath)
print("Done!")
