import AppKit

class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class CharacterContentView: NSView {
    weak var character: WalkerCharacter?

    private var isDragging = false
    private var dragOffset: CGFloat = 0
    private var windowOriginBeforeDrag: NSPoint = .zero
    private var mouseStartScreen: NSPoint = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }

        let screenPoint = window?.convertPoint(toScreen: convert(localPoint, to: nil)) ?? .zero
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        let flippedY = primaryScreen.frame.height - screenPoint.y

        // Pass clicks below the dock top edge through to the dock
        let dockTopY = primaryScreen.visibleFrame.origin.y
        if screenPoint.y < dockTopY {
            return nil
        }

        let captureRect = CGRect(x: screenPoint.x - 0.5, y: flippedY - 0.5, width: 1, height: 1)
        guard let windowID = window?.windowNumber, windowID > 0 else { return nil }

        if let image = CGWindowListCreateImage(
            captureRect,
            .optionIncludingWindow,
            CGWindowID(windowID),
            [.boundsIgnoreFraming, .bestResolution]
        ) {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            var pixel: [UInt8] = [0, 0, 0, 0]
            if let ctx = CGContext(
                data: &pixel, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                if pixel[3] > 30 {
                    return self
                }
                return nil
            }
        }

        let insetX = bounds.width * 0.2
        let insetY = bounds.height * 0.15
        let hitRect = bounds.insetBy(dx: insetX, dy: insetY)
        return hitRect.contains(localPoint) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = false
        dragOffset = 0
        windowOriginBeforeDrag = window?.frame.origin ?? .zero
        mouseStartScreen = NSEvent.mouseLocation
        character?.beginPointerTracking(at: mouseStartScreen)
    }

    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        let deltaX = current.x - mouseStartScreen.x
        dragOffset = deltaX

        // Once offset exceeds threshold, start dragging
        if !isDragging && abs(dragOffset) > 3 {
            isDragging = true
        }

        if isDragging {
            character?.continuePointerTracking(to: current)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !isDragging {
            // It was a click
            character?.handleClick()
        }
        isDragging = false
        dragOffset = 0
        character?.endPointerTracking(at: NSEvent.mouseLocation)
    }
}
