import AppKit

/// Full-screen overlay that highlights windows on hover and captures them on click.
/// Uses `screencapture -l<windowID>` for the actual capture — system binary, no TCC popup.
@MainActor
final class WindowPickerController {
    var onCapture: ((String) -> Void)?

    private var overlayPanels: [NSPanel] = []
    private var highlightLayers: [NSPanel: CAShapeLayer] = [:]
    private var hoveredWindowID: CGWindowID?

    // MARK: - Show / Dismiss

    func show() {
        for screen in NSScreen.screens {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = NSColor.black.withAlphaComponent(0.25)
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.acceptsMouseMovedEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let layer = CAShapeLayer()
            layer.fillColor = NSColor.systemBlue.withAlphaComponent(0.12).cgColor
            layer.strokeColor = NSColor.systemBlue.withAlphaComponent(0.8).cgColor
            layer.lineWidth = 3

            let overlayView = PickerOverlayView(frame: panel.contentView!.bounds)
            overlayView.autoresizingMask = [.width, .height]
            overlayView.wantsLayer = true
            overlayView.layer?.addSublayer(layer)
            overlayView.onMoved = { [weak self] in self?.handleMouseMoved() }
            overlayView.onClicked = { [weak self] in self?.handleClick() }
            panel.contentView?.addSubview(overlayView)

            highlightLayers[panel] = layer
            panel.orderFrontRegardless()
            overlayPanels.append(panel)
        }
    }

    func dismiss() {
        for panel in overlayPanels {
            panel.orderOut(nil)
        }
        overlayPanels.removeAll()
        highlightLayers.removeAll()
        hoveredWindowID = nil
    }

    // MARK: - Hit testing

    private func handleMouseMoved() {
        let cgPoint = appKitToCG(NSEvent.mouseLocation)

        guard let hit = hitTestWindow(at: cgPoint) else {
            clearHighlight()
            return
        }

        hoveredWindowID = hit.id
        highlightWindow(cgRect: hit.bounds)
    }

    private func handleClick() {
        guard let windowID = hoveredWindowID else { return }
        captureWindow(windowID)
    }

    private struct WindowHit {
        let id: CGWindowID
        let bounds: CGRect
    }

    private func hitTestWindow(at point: CGPoint) -> WindowHit? {
        let myPID = ProcessInfo.processInfo.processIdentifier
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for info in infoList {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  pid != myPID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"], let y = boundsDict["Y"],
                  let w = boundsDict["Width"], let h = boundsDict["Height"],
                  w > 1, h > 1
            else { continue }

            let rect = CGRect(x: x, y: y, width: w, height: h)
            if rect.contains(point) {
                let wid = info[kCGWindowNumber as String] as? CGWindowID ?? 0
                return WindowHit(id: wid, bounds: rect)
            }
        }
        return nil
    }

    // MARK: - Highlight

    private func highlightWindow(cgRect: CGRect) {
        let appKitRect = cgToAppKit(cgRect)

        for (panel, layer) in highlightLayers {
            let localRect = panel.convertFromScreen(appKitRect)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.path = CGPath(roundedRect: localRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
            CATransaction.commit()
        }
    }

    private func clearHighlight() {
        hoveredWindowID = nil
        for layer in highlightLayers.values {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.path = nil
            CATransaction.commit()
        }
    }

    // MARK: - Capture via CGWindowListCreateImage (uses app's Screen Recording TCC)

    private func captureWindow(_ windowID: CGWindowID) {
        guard CGPreflightScreenCaptureAccess() else {
            NSLog("[WindowPicker] Screen capture not permitted — skipping (no popup)")
            return
        }

        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            NSLog("[WindowPicker] CGWindowListCreateImage failed for window %d", windowID)
            return
        }

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let path = "/tmp/com.ericclemmons.Aside-\(timestamp).png"
        if writeCGImageAsPNG(cgImage, to: path) {
            onCapture?(path)
        }
    }

    private func writeCGImageAsPNG(_ image: CGImage, to path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            NSLog("[WindowPicker] Failed to create image destination")
            return false
        }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }

    // MARK: - Coordinate helpers

    private func appKitToCG(_ point: NSPoint) -> CGPoint {
        guard let mainHeight = NSScreen.screens.first?.frame.height else { return CGPoint(x: point.x, y: point.y) }
        return CGPoint(x: point.x, y: mainHeight - point.y)
    }

    private func cgToAppKit(_ rect: CGRect) -> NSRect {
        guard let mainHeight = NSScreen.screens.first?.frame.height else { return rect }
        return NSRect(x: rect.origin.x, y: mainHeight - rect.origin.y - rect.height, width: rect.width, height: rect.height)
    }
}

// MARK: - Custom view for mouse events in non-activating panel

private class PickerOverlayView: NSView {
    var onMoved: (() -> Void)?
    var onClicked: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        onMoved?()
    }

    override func mouseDown(with event: NSEvent) {
        onClicked?()
    }
}
