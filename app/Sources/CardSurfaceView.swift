import AppKit

final class CardSurfaceView: NSView {
    var onDragMove: ((NSPoint) -> Void)?
    var onDragEnd: (() -> Void)?
    var onOpenDashboard: (() -> Void)?
    var menuProvider: (() -> NSMenu)?

    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint?
    private var didDrag = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startMouse = dragStartMouse, let startOrigin = dragStartOrigin else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - startMouse.x
        let dy = current.y - startMouse.y
        if hypot(dx, dy) >= 3 { didDrag = true }
        let rawOrigin = NSPoint(
            x: startOrigin.x + dx,
            y: startOrigin.y + dy
        )
        onDragMove?(rawOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let wasClick = !didDrag
        dragStartMouse = nil
        dragStartOrigin = nil
        didDrag = false
        if wasClick, local.x >= bounds.width - 72, local.y <= 36 {
            onOpenDashboard?()
            return
        }
        onDragEnd?()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
