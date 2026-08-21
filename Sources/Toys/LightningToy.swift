import CoreGraphics
import Foundation

/// Branching bolts with a screen flash. Tap to strike where you touched.
final class LightningToy: PixelToy {
    override var title: String { "Lightning" }
    override var emoji: String { "⚡" }
    override var pixelHeight: Int { 30 }

    private struct Seg { var x0: Double, y0: Double, x1: Double, y1: Double, gen: Int }

    private var segs: [Seg] = []
    private var life = 0.0
    private var flash = 0.0
    private var nextStrike = 1.0
    private var w = 0, h = 0
    private var rng = RNG(seed: 0x11B7)

    override func resized(to buf: PixelBuffer) { w = buf.width; h = buf.height }

    override func tap(at p: CGPoint, size: CGSize) {
        guard w > 0, size.width > 0 else { return }
        strike(at: Double(p.x / size.width * CGFloat(w)))
    }

    private func strike(at x: Double) {
        segs = []
        bolt(from: (x, 0), to: (x + rng.range(-12, 12), Double(h)), gen: 0)
        life = 0.7
        flash = 0.35
        nextStrike = rng.range(0.6, 1.9)
    }

    private func bolt(from a: (Double, Double), to b: (Double, Double), gen: Int) {
        guard gen < 6, segs.count < 700 else { return }
        let steps = max(3, Int((b.1 - a.1) / 2.2))
        var p = a
        for i in 1...steps {
            let f = Double(i) / Double(steps)
            let jitter = rng.range(-2.6, 2.6) * (1 - f * 0.5)
            let n = (a.0 + (b.0 - a.0) * f + jitter, a.1 + (b.1 - a.1) * f)
            segs.append(Seg(x0: p.0, y0: p.1, x1: n.0, y1: n.1, gen: gen))
            // occasional fork
            if gen < 3, rng.d() < 0.10 {
                // forks lean, but they still travel mostly downward
                let drop = rng.range(9, 20)
                let lean = rng.range(-0.55, 0.55) * drop
                bolt(from: n, to: (n.0 + lean, n.1 + drop), gen: gen + 1)
            }
            p = n
        }
    }

    override func update(dt: Double, size: CGSize) {
        _ = buffer(for: size)
        life = max(0, life - dt)
        flash = max(0, flash - dt * 1.6)
        nextStrike -= dt
        if nextStrike <= 0 { strike(at: rng.range(Double(w) * 0.1, Double(w) * 0.9)) }
    }

    override func renderPixels(into buf: PixelBuffer) {
        let f = flash / 0.35
        for y in 0..<buf.height {
            let g = Double(y) / Double(buf.height)
            buf.fill(0, y, buf.width, 1,
                     rgb(Int(6 + 34 * f + 12 * (1 - g)), Int(8 + 38 * f + 14 * (1 - g)),
                         Int(20 + 60 * f + 26 * (1 - g))))
        }
        guard life > 0 else { return }
        let fade = min(1.0, life / 0.35)
        for s in segs {
            let bright = fade * (s.gen == 0 ? 1.0 : 0.55 / Double(s.gen))
            line(buf, s, rgb(150, 190, 255), 0.35 * bright, spread: 2)
            line(buf, s, rgb(230, 240, 255), bright, spread: 0)
        }
    }

    private func line(_ b: PixelBuffer, _ s: Seg, _ c: UInt32, _ a: Double, spread: Int) {
        let steps = max(1, Int(max(abs(s.x1 - s.x0), abs(s.y1 - s.y0))))
        for i in 0...steps {
            let f = Double(i) / Double(steps)
            let x = Int(s.x0 + (s.x1 - s.x0) * f)
            let y = Int(s.y0 + (s.y1 - s.y0) * f)
            if spread == 0 {
                b.blend(x, y, c, a)
            } else {
                for dy in -spread...spread {
                    for dx in -spread...spread {
                        b.blend(x + dx, y + dy, c, a / Double(1 + abs(dx) + abs(dy)))
                    }
                }
            }
        }
    }
}
