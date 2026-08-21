import CoreGraphics
import Foundation

/// Pong that plays itself. Two imperfect AIs down the long axis. 30 points of
/// vertical travel on a surface with no tactile feedback made it miserable to
/// actually control, so nobody controls it.
final class PongToy: PixelToy {
    override var title: String { "Pong (AI vs AI)" }
    override var emoji: String { "🏓" }
    override var pixelHeight: Int { 24 }

    private var w = 0, h = 0
    private var ballX = 0.0, ballY = 0.0
    private var vx = 150.0, vy = 46.0
    private var leftY = 0.0, rightY = 0.0
    private var leftErr = 0.0, rightErr = 0.0
    private var reErr = 0.0
    private var leftScore = 0, rightScore = 0
    private let paddleH = 9.0
    private var flash = 0.0
    private var trail: [(Double, Double)] = []
    private var rng = RNG(seed: 0x9046)

    override func resized(to buf: PixelBuffer) {
        w = buf.width; h = buf.height
        leftY = Double(h) / 2; rightY = leftY
        serve(toRight: true)
    }

    private func serve(toRight: Bool) {
        ballX = Double(w) / 2; ballY = Double(h) / 2
        vx = (toRight ? 1 : -1) * rng.range(150, 200)
        vy = rng.range(-42, 42)
        trail = []
    }

    override func update(dt: Double, size: CGSize) {
        _ = buffer(for: size)
        flash = max(0, flash - dt)
        ballX += vx * dt
        ballY += vy * dt
        trail.append((ballX, ballY))
        if trail.count > 9 { trail.removeFirst() }

        if ballY < 1 { ballY = 1; vy = abs(vy) }
        if ballY > Double(h) - 1 { ballY = -abs(vy) * 0 + Double(h) - 1; vy = -abs(vy) }

        // Each side aims at the ball but with a drifting error, refreshed every
        // so often. Occasionally the error is big enough to miss, which is what
        // keeps the score moving instead of an endless rally.
        reErr -= dt
        if reErr <= 0 {
            reErr = rng.range(0.5, 1.4)
            leftErr = rng.range(-4, 4) + (rng.d() < 0.12 ? rng.range(-11, 11) : 0)
            rightErr = rng.range(-4, 4) + (rng.d() < 0.12 ? rng.range(-11, 11) : 0)
        }
        let speed = 74.0
        if vx < 0 {
            leftY += max(-speed * dt, min(speed * dt, (ballY + leftErr) - leftY))
        } else {
            leftY += max(-30 * dt, min(30 * dt, Double(h) / 2 - leftY))
        }
        if vx > 0 {
            rightY += max(-speed * dt, min(speed * dt, (ballY + rightErr) - rightY))
        } else {
            rightY += max(-30 * dt, min(30 * dt, Double(h) / 2 - rightY))
        }
        leftY = max(paddleH / 2, min(Double(h) - paddleH / 2, leftY))
        rightY = max(paddleH / 2, min(Double(h) - paddleH / 2, rightY))

        let px = Double(w) - 6.0
        if vx > 0, ballX >= px, ballX < px + 4, abs(ballY - rightY) < paddleH / 2 + 1 {
            vx = -abs(vx) * 1.02
            vy += (ballY - rightY) * 5
            flash = 0.12
        }
        if vx < 0, ballX <= 6, ballX > 2, abs(ballY - leftY) < paddleH / 2 + 1 {
            vx = abs(vx) * 1.02
            vy += (ballY - leftY) * 5
            flash = 0.12
        }
        vx = max(-300, min(300, vx))
        vy = max(-110, min(110, vy))
        if ballX < 0 { rightScore += 1; serve(toRight: false) }
        if ballX > Double(w) { leftScore += 1; serve(toRight: true) }
    }

    override func renderPixels(into buf: PixelBuffer) {
        buf.clear(flash > 0 ? rgb(24, 24, 28) : rgb(10, 10, 12))
        for y in stride(from: 1, to: buf.height, by: 4) {
            buf.fill(buf.width / 2, y, 1, 2, rgb(60, 60, 68))
        }
        for (i, p) in trail.enumerated() {
            let a = Double(i) / Double(max(1, trail.count)) * 0.5
            buf.blend(Int(p.0), Int(p.1), rgb(200, 220, 255), a)
        }
        buf.fill(4, Int(leftY - paddleH / 2), 2, Int(paddleH), rgb(220, 110, 110))
        buf.fill(buf.width - 6, Int(rightY - paddleH / 2), 2, Int(paddleH), rgb(120, 200, 255))
        buf.fill(Int(ballX) - 1, Int(ballY) - 1, 2, 2, rgb(240, 244, 248))

        let l = "\(leftScore)", r = "\(rightScore)"
        MicroFont.draw(l, into: buf, x: buf.width / 2 - 12, y: 2, color: rgb(150, 150, 160))
        MicroFont.draw(r, into: buf, x: buf.width / 2 + 8, y: 2, color: rgb(150, 150, 160))
    }
}
