import AppKit

enum CardGeometry {
    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    static let edgeMargin: CGFloat = 14
    static let clampMargin: CGFloat = 10

    static func clampedOrigin(
        _ origin: NSPoint,
        size: NSSize,
        in visible: NSRect,
        ring: CGFloat,
        margin: CGFloat = clampMargin
    ) -> NSPoint {
        let minX = visible.minX + margin - ring
        let maxX = max(minX, visible.maxX - margin - size.width + ring)
        let minY = visible.minY + margin - ring
        let maxY = max(minY, visible.maxY - margin - size.height + ring)
        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    static func cornerOrigin(
        _ corner: Corner,
        size: NSSize,
        in visible: NSRect,
        ring: CGFloat,
        margin: CGFloat = edgeMargin
    ) -> NSPoint {
        switch corner {
        case .topLeft:
            return NSPoint(x: visible.minX + margin - ring, y: visible.maxY - margin - size.height + ring)
        case .topRight:
            return NSPoint(x: visible.maxX - margin - size.width + ring, y: visible.maxY - margin - size.height + ring)
        case .bottomLeft:
            return NSPoint(x: visible.minX + margin - ring, y: visible.minY + margin - ring)
        case .bottomRight:
            return NSPoint(x: visible.maxX - margin - size.width + ring, y: visible.minY + margin - ring)
        }
    }
}
