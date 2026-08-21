import CoreGraphics
import Foundation

/// Rockets, bursts and drifting embers. Tap anywhere to launch one there.
final class FireworksToy: PixelToy {
    override var title: String { "Fireworks" }
    override var emoji: String { "🎆" }
    override var pixelHeight: Int { 30 }

    private struct P {
        var x: Double, y: Double, vx: Double, vy: Double
        var life: Double, maxLife: Double
        var hue: Double, rocket: Bool, targetY: Double
    }

    private var parts: [P] = []
    private var w = 0, h = 0
    private var nextLaunch = 0.4
    private var rng = RNG(seed: 0xF16E)

    override func resized(to buf: PixelBuffer) {
        w = buf.width; h = buf.height
        parts = []
        for _ in 0..<3 { launch(at: CGFloat(rng.range(Double(w) * 0.1, Double(w) * 0.9))) }
    }

    override func tap(at p: CGPoint, size: CGSize) {
        guard w > 0, size.width > 0 else { return }
        launch(at: p.x / size.width * CGFloat(w))
    }

    private func launch(at x: CGFloat) {
        parts.append(P(x: Double(x), y: Double(h), vx: rng.range(-6, 6), vy: -rng.range(26, 38),
                       life: 3, maxLife: 3, hue: rng.d(), rocket: true,
                       targetY: rng.range(3, Double(h) * 0.45)))
    }

    override func update(dt: Double, size: CGSize) {
        _ = buffer(for: size)
        nextLaunch -= dt
        if nextLaunch <= 0 {
            nextLaunch = rng.range(0.22, 0.7)
            launch(at: CGFloat(rng.range(Double(w) * 0.1, Double(w) * 0.9)))
        }
        var bursts: [P] = []
        for i in parts.indices {
            parts[i].x += parts[i].vx * dt
            parts[i].y += parts[i].vy * dt
            parts[i].life -= dt
            if parts[i].rocket {
                if parts[i].y <= parts[i].targetY {
                    parts[i].life = 0
                    bursts.append(parts[i])
                }
            } else {
                parts[i].vy += 26 * dt          // gravity
                parts[i].vx *= 1 - 0.9 * dt     // drag
                parts[i].vy *= 1 - 0.9 * dt
            }
        }
        parts.removeAll { $0.life <= 0 }
        for b in bursts { explode(b) }
        if parts.count > 900 { parts.removeFirst(parts.count - 900) }
    }

    private func explode(_ r: P) {
        let n = 38 + rng.int(26)
        let speed = rng.range(16, 30)
        for k in 0..<n {
            let a = Double(k) / Double(n) * 2 * .pi + rng.range(-0.08, 0.08)
            let s = speed * rng.range(0.55, 1.15)
            let life = rng.range(1.0, 2.0)
            parts.append(P(x: r.x, y: r.y, vx: cos(a) * s, vy: sin(a) * s * 0.75,
                           life: life, maxLife: life,
                           hue: r.hue + rng.range(-0.06, 0.06), rocket: false, targetY: 0))
        }
    }

    override func renderPixels(into buf: PixelBuffer) {
        buf.clear(rgb(4, 4, 14))
        for p in parts {
            let f = max(0, min(1, p.life / p.maxLife))
            let color = p.rocket ? rgb(255, 240, 200) : hsv(p.hue, 0.65, 1.0)
            let a = p.rocket ? 1.0 : min(1.0, f * 1.5)
            buf.blend(Int(p.x), Int(p.y), color, a)
            if p.rocket {
                buf.blend(Int(p.x), Int(p.y) + 1, rgb(255, 170, 60), 0.6)
                buf.blend(Int(p.x), Int(p.y) + 2, rgb(200, 90, 30), 0.3)
            } else if f > 0.35 {
                buf.blend(Int(p.x) + 1, Int(p.y), color, a * 0.55)
                buf.blend(Int(p.x), Int(p.y) + 1, color, a * 0.55)
                buf.blend(Int(p.x) - 1, Int(p.y), color, a * 0.35)
            }
        }
    }
}
