import AppKit

/// The animated canvas that lives inside the Touch Bar.
final class ToyView: NSView {
    var toy: Toy {
        didSet { needsDisplay = true }
    }
    /// 30fps: smooth enough for a 30pt strip, half the battery of 60.
    var fps: Double = 30

    private(set) var framesDrawn = 0
    var onWindowChange: ((Bool) -> Void)?
    private var timer: Timer?
    private var lastTick = CFAbsoluteTimeGetCurrent()

    init(toy: Toy) {
        self.toy = toy
        super.init(frame: NSRect(x: 0, y: 0, width: 1004, height: 30))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        // Same opt-in as the buttons. Without this the toys never see a tap,
        // so fire, hyperspace and Flap would all be inert on the bar.
        allowedTouchTypes = [.direct]
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Let the Touch Bar stretch us into whatever space is left over.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 30)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window == nil ? stop() : start()
        onWindowChange?(window != nil)
    }

    func resetFrameCount() { framesDrawn = 0 }

    func start() {
        guard timer == nil else { return }
        lastTick = CFAbsoluteTimeGetCurrent()
        let t = Timer(timeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common so animation survives menu tracking and live resize.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = CFAbsoluteTimeGetCurrent()
        // Clamp dt so waking from sleep doesn't teleport everything.
        let dt = min(0.1, max(0.0001, now - lastTick))
        lastTick = now
        toy.update(dt: dt, size: bounds.size)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(bounds)
        toy.draw(in: ctx, size: bounds.size)
        framesDrawn += 1
    }

    override func mouseDown(with event: NSEvent) {
        toy.tap(at: convert(event.locationInWindow, from: nil), size: bounds.size)
    }

    override func mouseDragged(with event: NSEvent) {
        toy.tap(at: convert(event.locationInWindow, from: nil), size: bounds.size)
    }

    override func touchesBegan(with event: NSEvent) { forward(event, matching: .began) }
    override func touchesMoved(with event: NSEvent) { forward(event, matching: .moved) }

    private func forward(_ event: NSEvent, matching phase: NSTouch.Phase) {
        for t in event.touches(matching: phase, in: self) {
            toy.tap(at: t.location(in: self), size: bounds.size)
        }
    }
}
