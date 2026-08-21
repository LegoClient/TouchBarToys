import CoreGraphics
import Foundation

/// Snow that actually settles. The drifts build up along the bottom and slump
/// sideways as they get steep. Tap for a gust of wind.
final class SnowToy: PixelToy {
    override var title: String { "Snowfall" }
    override var emoji: String { "❄️" }
    override var pixelHeight: Int { 30 }

    private struct Flake { var x: Double, y: Double, vy: Double, sway: Double, size: Double }

    private var flakes: [Flake] = []
    private var drift: [Double] = []
    private var w = 0, h = 0
    private var wind = 0.0
    private var gust = 0.0
    private var t = 0.0
    private var rng = RNG(seed: 0x5C0F)

    override func resized(to buf: PixelBuffer) {
        w = buf.width; h = buf.height
        // pre-seed a gently rolling snowline so it doesn't start bare
        drift = (0..<w).map { x -> Double in
            let fx = Double(x)
            let a: Double = 2.2 * sin(fx * 0.013)
            let b: Double = 1.4 * sin(fx * 0.041 + 1.1)
            return 3.0 + a + b
        }
        flakes = (0..<230).map { _ in newFlake(anywhere: true) }
    }

    private func newFlake(anywhere: Bool) -> Flake {
        Flake(x: rng.range(0, Double(max(1, w))),
              y: anywhere ? rng.range(0, Double(max(1, h))) : -2,
              vy: rng.range(6, 20), sway: rng.range(0, 6.28), size: rng.range(0.4, 1.6))
    }

    override func tap(at p: CGPoint, size: CGSize) {
        guard size.width > 0 else { return }
        gust = p.x / size.width < 0.5 ? -1.0 : 1.0
    }

    override func update(dt: Double, size: CGSize) {
        _ = buffer(for: size)
        t += dt
        gust *= 1 - 1.1 * dt
        wind = sin(t * 0.35) * 7 + gust * 46

        for i in flakes.indices {
            flakes[i].y += flakes[i].vy * dt
            flakes[i].x += (wind * flakes[i].size * 0.35
                            + sin(t * 1.7 + flakes[i].sway) * 6) * dt
            if flakes[i].x < -2 { flakes[i].x += Double(w) }
            if flakes[i].x > Double(w) + 2 { flakes[i].x -= Double(w) }

            let col = Int(flakes[i].x)
            if col >= 0, col < w {
                let surface = Double(h) - drift[col]
                if flakes[i].y >= surface - 1 {
                    drift[col] += 0.5 * flakes[i].size
                    flakes[i] = newFlake(anywhere: false)
                }
            }
            if flakes[i].y > Double(h) { flakes[i] = newFlake(anywhere: false) }
        }
        settle(dt)
    }

    /// Steep drifts slump into their neighbours.
    private func settle(_ dt: Double) {
        guard w > 2 else { return }
        for x in 1..<(w - 1) {
            let l = drift[x - 1], r = drift[x + 1], c = drift[x]
            if c - l > 1.6 { let m = (c - l) * 0.25; drift[x] -= m; drift[x - 1] += m }
            if c - r > 1.6 { let m = (c - r) * 0.25; drift[x] -= m; drift[x + 1] += m }
        }
        // don't let it bury the whole bar
        let cap = Double(h) * 0.6
        for x in 0..<w where drift[x] > cap { drift[x] = cap }
    }

    override func renderPixels(into buf: PixelBuffer) {
        for y in 0..<buf.height {
            let f = Double(y) / Double(buf.height)
            buf.fill(0, y, buf.width, 1, rgb(Int(10 + 18 * f), Int(14 + 24 * f), Int(30 + 40 * f)))
        }
        for x in 0..<min(w, buf.width) {
            let d = Int(drift[x])
            if d > 0 {
                buf.fill(x, buf.height - d, 1, d, rgb(236, 242, 252))
                buf.px(x, buf.height - d, rgb(255, 255, 255))
            }
        }
        for f in flakes {
            let a = 0.5 + 0.5 * min(1.0, f.size)
            buf.blend(Int(f.x), Int(f.y), rgb(255, 255, 255), a)
            if f.size > 1.2 {
                buf.blend(Int(f.x) + 1, Int(f.y), rgb(230, 240, 255), a * 0.5)
                buf.blend(Int(f.x), Int(f.y) + 1, rgb(230, 240, 255), a * 0.5)
            }
        }
    }
}
