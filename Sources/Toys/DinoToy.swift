import CoreGraphics
import Foundation

/// The offline dinosaur. Tap to jump. The bar is already the right shape.
final class DinoToy: PixelToy {
    override var title: String { "Dino Runner" }
    override var emoji: String { "🦖" }
    override var pixelHeight: Int { 24 }

    private enum State { case ready, running, dead }

    private var state: State = .ready
    private var w = 0, h = 0
    private var groundY = 0
    private var dinoX = 0
    private var y = 0.0, vy = 0.0
    private var speed = 110.0
    private var dist = 0.0
    private var score = 0, best = 0
    private var t = 0.0, deadFor = 0.0
    private var night = false
    private var obstacles: [(x: Double, w: Int, h: Int, bird: Bool)] = []
    private var clouds: [(x: Double, y: Int)] = []
    private var rng = RNG(seed: 0xD140)

    override func resized(to buf: PixelBuffer) {
        w = buf.width; h = buf.height
        groundY = h - 4
        dinoX = Int(Double(w) * 0.13)
        clouds = (0..<5).map { _ in (x: rng.range(0, Double(w)), y: 2 + rng.int(5)) }
        reset()
    }

    private func reset() {
        y = Double(groundY); vy = 0; speed = 110; dist = 0; score = 0
        obstacles = []
        var x = Double(w) * 0.8
        while x < Double(w) * 2.2 {
            obstacles.append(spawn(at: x))
            x += rng.range(150, 300)
        }
    }

    private func spawn(at x: Double) -> (x: Double, w: Int, h: Int, bird: Bool) {
        let bird = rng.d() < 0.22
        if bird { return (x: x, w: 8, h: 5, bird: true) }
        let tall = rng.d() < 0.5
        return (x: x, w: 3 + rng.int(4), h: tall ? 9 : 6, bird: false)
    }

    override func tap(at p: CGPoint, size: CGSize) {
        switch state {
        case .ready: state = .running; vy = -132
        case .running: if y >= Double(groundY) - 0.5 { vy = -132 }
        case .dead: if deadFor > 0.35 { best = max(best, score); reset(); state = .ready }
        }
    }

    override func update(dt: Double, size: CGSize) {
        _ = buffer(for: size)
        t += dt
        for i in clouds.indices {
            clouds[i].x -= 9 * dt
            if clouds[i].x < -14 { clouds[i].x = Double(w) + rng.range(0, 60); clouds[i].y = 2 + rng.int(5) }
        }
        switch state {
        case .ready:
            y = Double(groundY)
        case .dead:
            deadFor += dt
        case .running:
            speed = min(260, speed + dt * 4)
            dist += speed * dt
            score = Int(dist / 12)
            night = (score / 260) % 2 == 1
            vy += 430 * dt
            y = min(Double(groundY), y + vy * dt)

            for i in obstacles.indices { obstacles[i].x -= speed * dt }
            if let first = obstacles.first, first.x < -20 {
                obstacles.removeFirst()
                let lastX = obstacles.last?.x ?? Double(w)
                obstacles.append(spawn(at: lastX + rng.range(150, 320)))
            }
            for o in obstacles where hits(o) { die() }
        }
    }

    private func hits(_ o: (x: Double, w: Int, h: Int, bird: Bool)) -> Bool {
        let dx0 = Double(dinoX), dx1 = Double(dinoX + 8)
        guard dx1 > o.x + 1, dx0 < o.x + Double(o.w) - 1 else { return false }
        let dinoTop = y - 11
        if o.bird {
            let by = Double(groundY - 11), bh = Double(o.h)
            return dinoTop < by + bh && y > by
        }
        return y > Double(groundY - o.h)
    }

    private func die() {
        guard state == .running else { return }
        state = .dead; deadFor = 0; best = max(best, score)
    }

    override func renderPixels(into buf: PixelBuffer) {
        let bg = night ? rgb(16, 18, 30) : rgb(247, 247, 247)
        let ink = night ? rgb(226, 226, 235) : rgb(70, 70, 70)
        buf.clear(bg)

        for c in clouds {
            buf.fill(Int(c.x), c.y, 9, 2, night ? rgb(46, 48, 62) : rgb(214, 214, 214))
            buf.fill(Int(c.x) + 2, c.y - 1, 5, 1, night ? rgb(46, 48, 62) : rgb(214, 214, 214))
        }

        buf.fill(0, groundY + 1, buf.width, 1, ink)
        for x in stride(from: Int(dist) % 14, to: buf.width, by: 14) {
            buf.px(x, groundY + 3, ink)
        }

        for o in obstacles {
            let x = Int(o.x)
            if o.bird {
                let flap = Int(t * 7) % 2 == 0
                let by = groundY - 11
                buf.fill(x + 2, by + 2, 5, 2, ink)
                if flap { buf.fill(x, by, 4, 2, ink) } else { buf.fill(x, by + 4, 4, 2, ink) }
                buf.fill(x + 6, by + 1, 2, 1, ink)
            } else {
                buf.fill(x, groundY - o.h, o.w, o.h, ink)
                buf.fill(x - 1, groundY - o.h + 2, 1, 3, ink)
                buf.fill(x + o.w, groundY - o.h + 3, 1, 3, ink)
            }
        }

        dino(buf, dinoX, Int(y), ink: ink, bg: bg)

        let label = state == .dead ? "GAME OVER \(score)" : "\(score)"
        MicroFont.draw(label, into: buf, x: buf.width - MicroFont.width(label) - 4, y: 2, color: ink)
        if state == .ready {
            MicroFont.draw("TAP TO RUN", into: buf, x: dinoX + 16, y: 4, color: ink)
        }
    }

    /// `by` is the y of the dino's feet.
    private func dino(_ b: PixelBuffer, _ x: Int, _ by: Int, ink: UInt32, bg: UInt32) {
        let top = by - 11
        b.fill(x, top + 4, 6, 6, ink)          // body
        b.fill(x + 5, top, 5, 5, ink)          // head
        b.px(x + 8, top + 1, bg)               // eye
        b.fill(x + 9, top + 3, 2, 1, ink)      // snout
        b.fill(x - 2, top + 5, 3, 2, ink)      // tail
        if state == .running && by >= groundY - 1 {
            // alternate the legs only while actually on the ground
            let step = Int(t * 12) % 2 == 0
            b.fill(x + 1, top + 10, 2, 2, step ? ink : bg)
            b.fill(x + 4, top + 10, 2, 2, step ? bg : ink)
        } else {
            b.fill(x + 1, top + 10, 2, 1, ink)
            b.fill(x + 4, top + 10, 2, 1, ink)
        }
        b.fill(x + 2, top + 9, 3, 1, ink)
    }
}
