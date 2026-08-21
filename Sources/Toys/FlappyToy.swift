import CoreGraphics
import Foundation

/// Tap-to-flap. The Touch Bar is a terrible place for a game, which is the point.
final class FlappyToy: PixelToy {
    override var title: String { "Flap (tap to play)" }
    override var emoji: String { "🐤" }
    override var pixelHeight: Int { 24 }

    private enum State { case ready, playing, dead }

    private let sky      = rgb(92, 188, 214)
    private let skyDark  = rgb(72, 166, 196)
    private let cloud    = rgb(222, 244, 250)
    private let pipeBody = rgb(88, 198, 88)
    private let pipeDark = rgb(52, 148, 56)
    private let pipeLite = rgb(150, 226, 150)
    private let ground   = rgb(222, 196, 118)
    private let grass    = rgb(126, 200, 84)
    private let ink      = rgb(24, 24, 24)
    private let body     = rgb(252, 216, 72)
    private let beak     = rgb(248, 140, 44)

    private let gap = 11.0
    private let pipeW = 9
    private let spacing = 150.0
    private let scrollSpeed = 96.0
    private let gravity = 150.0
    private let flapV = -52.0

    private var state: State = .ready
    private var w = 0, h = 0
    private var birdX = 0.0
    private var birdY = 0.0
    private var vy = 0.0
    private var pipes: [(x: Double, gapY: Double, scored: Bool)] = []
    private var score = 0
    private var best = 0
    private var t = 0.0
    private var deadFor = 0.0
    private var clouds: [(x: Double, y: Int, w: Int)] = []
    private var rng = RNG(seed: 0xF1A9)

    override func resized(to buf: PixelBuffer) {
        w = buf.width; h = buf.height
        birdX = Double(w) * 0.22
        clouds = (0..<7).map { _ in
            (x: rng.range(0, Double(w)), y: 2 + rng.int(6), w: 6 + rng.int(9))
        }
        reset()
    }

    private func reset() {
        birdY = Double(h) / 2
        vy = 0
        score = 0
        pipes = []
        let groundY = Double(h) - 3
        var x = Double(w) * 0.75
        while x < Double(w) + spacing * 2 {
            pipes.append((x: x, gapY: rng.range(gap / 2 + 2, groundY - gap / 2 - 1), scored: false))
            x += spacing
        }
    }

    override func tap(at p: CGPoint, size: CGSize) {
        switch state {
        case .ready:
            state = .playing
            vy = flapV
        case .playing:
            vy = flapV
        case .dead:
            if deadFor > 0.35 { reset(); state = .ready }
        }
    }

    override func update(dt: Double, size: CGSize) {
        _ = buffer(for: size)
        t += dt
        for i in clouds.indices {
            clouds[i].x -= 8 * dt
            if clouds[i].x < -20 { clouds[i].x = Double(w) + rng.range(0, 40); clouds[i].y = 2 + rng.int(6) }
        }
        guard w > 0, h > 0 else { return }
        let groundY = Double(h) - 3

        switch state {
        case .ready:
            birdY = Double(h) / 2 + sin(t * 4) * 1.6
        case .dead:
            deadFor += dt
            vy = min(220, vy + gravity * dt)
            birdY = min(groundY - 2, birdY + vy * dt)
        case .playing:
            vy = min(200, vy + gravity * dt)
            birdY += vy * dt
            for i in pipes.indices {
                pipes[i].x -= scrollSpeed * dt
                if !pipes[i].scored && pipes[i].x + Double(pipeW) < birdX {
                    pipes[i].scored = true
                    score += 1
                    best = max(best, score)
                }
            }
            if let first = pipes.first, first.x < -Double(pipeW) - 4 {
                pipes.removeFirst()
                let lastX = pipes.last?.x ?? Double(w)
                pipes.append((x: lastX + spacing,
                              gapY: rng.range(gap / 2 + 2, groundY - gap / 2 - 1),
                              scored: false))
            }
            if birdY >= groundY - 2 || birdY <= 0 { die() }
            for p in pipes {
                let bx0 = birdX - 2, bx1 = birdX + 3
                if bx1 > p.x && bx0 < p.x + Double(pipeW) {
                    if birdY - 2 < p.gapY - gap / 2 || birdY + 2 > p.gapY + gap / 2 { die() }
                }
            }
        }
    }

    private func die() {
        guard state == .playing else { return }
        state = .dead
        deadFor = 0
        vy = -20
    }

    override func renderPixels(into buf: PixelBuffer) {
        // sky gradient
        for y in 0..<buf.height {
            let f = Double(y) / Double(buf.height)
            let c = rgb(Int(92 - 20 * f), Int(188 - 22 * f), Int(214 - 18 * f))
            buf.fill(0, y, buf.width, 1, c)
        }
        for c in clouds {
            buf.fill(Int(c.x), c.y, c.w, 2, cloud)
            buf.fill(Int(c.x) + 2, c.y - 1, c.w - 4, 1, cloud)
        }

        let groundY = buf.height - 3
        for p in pipes {
            let x = Int(p.x)
            let topH = Int(p.gapY - gap / 2)
            let botY = Int(p.gapY + gap / 2)
            drawPipe(buf, x: x, y: 0, h: topH, capAtBottom: true)
            drawPipe(buf, x: x, y: botY, h: groundY - botY, capAtBottom: false)
        }

        buf.fill(0, groundY, buf.width, 1, grass)
        buf.fill(0, groundY + 1, buf.width, buf.height - groundY - 1, ground)
        for x in stride(from: Int(t * scrollSpeed) % 6, to: buf.width, by: 6) {
            buf.px(x, groundY + 2, rgb(198, 172, 96))
        }

        bird(buf, Int(birdX), Int(birdY))

        let label = state == .dead ? "DEAD \(score)" : "\(score)"
        MicroFont.draw(label, into: buf, x: 4, y: 2, color: ink)
        MicroFont.draw(label, into: buf, x: 3, y: 1, color: rgb(255, 255, 255))
        if state == .ready {
            let msg = "TAP TO FLAP"
            let mw = MicroFont.width(msg)
            let mx = Int(birdX) + 14
            MicroFont.draw(msg, into: buf, x: mx + 1, y: buf.height / 2 - 2, color: ink)
            MicroFont.draw(msg, into: buf, x: mx, y: buf.height / 2 - 3, color: rgb(255, 255, 255))
            _ = mw
        }
        if state == .dead {
            for y in 0..<buf.height {
                for x in stride(from: (y % 2), to: buf.width, by: 2) {
                    buf.blend(x, y, rgb(180, 30, 30), 0.22)
                }
            }
        }
    }

    private func drawPipe(_ b: PixelBuffer, x: Int, y: Int, h: Int, capAtBottom: Bool) {
        guard h > 0 else { return }
        b.fill(x, y, pipeW, h, pipeBody)
        b.fill(x, y, 1, h, pipeDark)
        b.fill(x + pipeW - 1, y, 1, h, pipeDark)
        b.fill(x + 2, y, 1, h, pipeLite)
        let capY = capAtBottom ? y + h - 2 : y
        b.fill(x - 1, capY, pipeW + 2, 2, pipeBody)
        b.fill(x - 1, capY, 1, 2, pipeDark)
        b.fill(x + pipeW, capY, 1, 2, pipeDark)
    }

    private func bird(_ b: PixelBuffer, _ x: Int, _ y: Int) {
        let wingUp = state == .playing ? (vy < 0) : (Int(t * 6) % 2 == 0)
        b.fill(x - 2, y - 2, 5, 4, body)
        b.fill(x - 3, y - 1, 1, 2, body)
        b.px(x - 2, y - 2, ink); b.px(x + 2, y - 2, ink)
        b.px(x - 2, y + 1, ink); b.px(x + 2, y + 1, ink)
        b.px(x + 1, y - 1, rgb(255, 255, 255))       // eye white
        b.px(x + 2, y - 1, ink)                       // pupil
        b.fill(x + 3, y, 2, 1, beak)                  // beak
        if wingUp {
            b.fill(x - 2, y - 3, 3, 1, rgb(255, 255, 255))
        } else {
            b.fill(x - 2, y + 2, 3, 1, rgb(232, 190, 60))
        }
    }
}
