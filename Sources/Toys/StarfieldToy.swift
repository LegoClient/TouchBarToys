import CoreGraphics
import Foundation

/// Warp-speed starfield. Tap to punch it to lightspeed for a second.
final class StarfieldToy: PixelToy {
    override var title: String { "Hyperspace" }
    override var emoji: String { "✨" }
    override var pixelHeight: Int { 30 }

    private struct Star {
        var x: Double, y: Double, z: Double, pz: Double
        var tint: Int          // 0 white, 1 blue, 2 warm
    }

    private var stars: [Star] = []
    private var rng = RNG(seed: 0x5A17)
    private var warp: Double = 0
    private var t: Double = 0
    private var w = 0, h = 0

    override func resized(to buf: PixelBuffer) {
        w = buf.width; h = buf.height
        stars = (0..<520).map { _ in spawn(anywhere: true) }
    }

    private func spawn(anywhere: Bool) -> Star {
        // Bias x outward: on a 33:1 bar most of the action is horizontal.
        let z = anywhere ? rng.range(0.06, 1.0) : rng.range(0.86, 1.0)
        return Star(x: rng.range(-1, 1), y: rng.range(-1, 1), z: z, pz: z,
                    tint: rng.d() < 0.16 ? (rng.d() < 0.5 ? 1 : 2) : 0)
    }

    override func tap(at p: CGPoint, size: CGSize) { warp = 1.0 }

    override func update(dt: Double, size: CGSize) {
        _ = buffer(for: size)
        t += dt
        warp = max(0, warp - dt * 0.75)
        // A slow idle pulse keeps it moving even when nobody taps.
        let base = 0.42 + 0.10 * sin(t * 0.7)
        let speed = (base + 2.1 * warp * warp) * dt
        let cx = Double(w) / 2
        for i in stars.indices {
            stars[i].pz = stars[i].z
            stars[i].z -= speed
            var dead = stars[i].z <= 0.03
            if !dead {
                // Recycle stars that have already flown off the ends, otherwise
                // most of the budget sits invisible past the edges.
                let sx = cx + stars[i].x / stars[i].z * cx
                if sx < -30 || sx > Double(w) + 30 { dead = true }
            }
            if dead { stars[i] = spawn(anywhere: false) }
        }
    }

    override func renderPixels(into buf: PixelBuffer) {
        buf.clear(rgb(1, 1, 6))
        let cx = Double(buf.width) / 2, cy = Double(buf.height) / 2

        for s in stars {
            let sx = cx + s.x / s.z * cx
            let sy = cy + s.y / s.z * cy
            guard sx > -24, sx < Double(buf.width) + 24, sy > -8, sy < Double(buf.height) + 8
            else { continue }

            let bright = min(1.0, pow(1.0 - s.z, 0.65) * 1.25)
            let v = Int(70 + 185 * bright)
            let c: UInt32
            switch s.tint {
            case 1:  c = rgb(max(0, v - 55), max(0, v - 20), 255.clamped(v + 30))
            case 2:  c = rgb(255.clamped(v + 30), max(0, v - 25), max(0, v - 70))
            default: c = rgb(v, v, 255.clamped(v + 12))
            }

            // Streak from where the star was last frame — this is the warp look.
            let px = cx + s.x / s.pz * cx
            let py = cy + s.y / s.pz * cy
            let dist = abs(sx - px) + abs(sy - py)
            let steps = min(40, max(1, Int(dist)))
            for k in 0...steps {
                let f = Double(k) / Double(steps)
                buf.blend(Int(px + (sx - px) * f), Int(py + (sy - py) * f),
                          c, (0.18 + 0.82 * f) * (0.35 + 0.65 * bright))
            }
            // Give the near stars some body so they pop.
            if bright > 0.55 {
                buf.blend(Int(sx), Int(sy) - 1, c, 0.45 * bright)
                buf.blend(Int(sx), Int(sy) + 1, c, 0.45 * bright)
                if bright > 0.85 { buf.blend(Int(sx) + 1, Int(sy), c, 0.6) }
            }
        }
    }
}

private extension Int {
    func clamped(_ v: Int) -> Int { Swift.min(self, Swift.max(0, v)) }
}
