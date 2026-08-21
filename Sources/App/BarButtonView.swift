import AppKit

/// Touch Bar buttons we draw ourselves.
///
/// `NSButton` renders nothing in this app: not its title, not a symbol image,
/// not even its bezel; it comes out as an empty slot on the bar. It's the same
/// failure that made the status menu blank. Custom view drawing works, so
/// everything here is plain Bezier paths: no control artwork, no text, no image.
final class BarButtonView: NSView {
    enum Kind { case close, prev, next, rainbow }

    private let kind: Kind
    private var pressed = false
    var onTap: (() -> Void)?

    init(kind: Kind, width: CGFloat) {
        self.kind = kind
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 30))
        wantsLayer = true
        // Direct touches are not delivered to a custom view in the Touch Bar
        // unless it opts in. NSControl does this for you; a plain NSView gets
        // nothing, which is why the drawn buttons were inert.
        allowedTouchTypes = [.direct]
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        needsDisplay = true
        Log.write("button \(kind) mouseUp inside=\(inside)")
        if inside { onTap?() }
    }

    // Touch Bar taps arrive as direct touches, not clicks.
    override func touchesBegan(with event: NSEvent) {
        pressed = true
        needsDisplay = true
    }

    override func touchesEnded(with event: NSEvent) {
        pressed = false
        needsDisplay = true
        let touches = event.touches(matching: .ended, in: self)
        let inside = touches.isEmpty
            || touches.contains { bounds.contains($0.location(in: self)) }
        Log.write("button \(kind) touchEnded n=\(touches.count) inside=\(inside)")
        if inside { onTap?() }
    }

    override func touchesCancelled(with event: NSEvent) {
        pressed = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let plate = bounds.insetBy(dx: 2, dy: 2)
        NSColor(white: pressed ? 0.34 : 0.17, alpha: 1).setFill()
        NSBezierPath(roundedRect: plate, xRadius: 6, yRadius: 6).fill()

        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        NSColor.white.setStroke()
        NSColor.white.setFill()

        switch kind {
        case .close:
            let r: CGFloat = 5
            let p = NSBezierPath()
            p.lineWidth = 1.8
            p.lineCapStyle = .round
            p.move(to: NSPoint(x: c.x - r, y: c.y - r))
            p.line(to: NSPoint(x: c.x + r, y: c.y + r))
            p.move(to: NSPoint(x: c.x - r, y: c.y + r))
            p.line(to: NSPoint(x: c.x + r, y: c.y - r))
            p.stroke()

        case .next, .prev:
            let dir: CGFloat = kind == .next ? 1 : -1
            let p = NSBezierPath()
            p.move(to: NSPoint(x: c.x - 3.5 * dir, y: c.y + 6))
            p.line(to: NSPoint(x: c.x + 4.5 * dir, y: c.y))
            p.line(to: NSPoint(x: c.x - 3.5 * dir, y: c.y - 6))
            p.close()
            p.fill()

        case .rainbow:
            // A little arced rainbow, so the Control Strip slot is recognisable
            // without relying on an emoji glyph.
            let colors: [NSColor] = [
                .init(red: 1.00, green: 0.23, blue: 0.19, alpha: 1),
                .init(red: 1.00, green: 0.58, blue: 0.00, alpha: 1),
                .init(red: 1.00, green: 0.90, blue: 0.10, alpha: 1),
                .init(red: 0.20, green: 0.85, blue: 0.29, alpha: 1),
                .init(red: 0.20, green: 0.60, blue: 1.00, alpha: 1),
            ]
            let base = NSPoint(x: c.x, y: c.y - 6)
            for (i, color) in colors.enumerated() {
                let radius = 10.5 - CGFloat(i) * 1.9
                let arc = NSBezierPath()
                arc.appendArc(withCenter: base, radius: radius, startAngle: 12, endAngle: 168)
                arc.lineWidth = 1.9
                color.setStroke()
                arc.stroke()
            }
        }
    }
}
