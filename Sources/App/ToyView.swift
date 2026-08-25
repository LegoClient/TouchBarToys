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

    /// Brightness and volume, shown over the scene on a double tap.
    let controls = ControlPanel()
    var doubleTapEnabled = true
    private(set) var showControls = false
    private var lastTapAt: CFAbsoluteTime = 0
    private var lastTapX: CGFloat = 0
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

    func hideControls() {
        showControls = false
        controls.ended()
    }

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
        if showControls { controls.update(dt: dt) }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(bounds)
        toy.draw(in: ctx, size: bounds.size)
        if showControls {
            // the scene keeps running, dimmed, behind the sliders
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.74))
            ctx.fill(bounds)
            controls.draw(in: ctx, size: bounds.size)
        }
        framesDrawn += 1
    }

    // MARK: - Input

    /// A double tap toggles the control panel. Taps are still delivered to the
    /// scene as they happen, so games stay responsive; the cost is that rapid
    /// tapping can trip the gesture, which is why it can be turned off.
    /// Not private so the input path can be exercised by `--testgesture`.
    func began(at p: CGPoint) {
        let now = CFAbsoluteTimeGetCurrent()
        let isDouble = doubleTapEnabled
            && now - lastTapAt < 0.28
            && abs(p.x - lastTapX) < 44
        lastTapAt = isDouble ? 0 : now
        lastTapX = p.x

        if isDouble {
            showControls.toggle()
            if showControls { controls.refresh() } else { controls.ended() }
            needsDisplay = true
            return
        }
        if showControls {
            if controls.began(at: p, size: bounds.size) { hideControls() }
            needsDisplay = true
        } else {
            toy.tap(at: p, size: bounds.size)
        }
    }

    func moved(at p: CGPoint) {
        if showControls {
            controls.moved(at: p, size: bounds.size)
            needsDisplay = true
        } else {
            toy.tap(at: p, size: bounds.size)
        }
    }

    private func ended() { controls.ended() }

    override func mouseDown(with event: NSEvent) {
        began(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        moved(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) { ended() }

    override func touchesBegan(with event: NSEvent) {
        for t in event.touches(matching: .began, in: self) { began(at: t.location(in: self)) }
    }

    override func touchesMoved(with event: NSEvent) {
        for t in event.touches(matching: .moved, in: self) { moved(at: t.location(in: self)) }
    }

    override func touchesEnded(with event: NSEvent) { ended() }
    override func touchesCancelled(with event: NSEvent) { ended() }
}
