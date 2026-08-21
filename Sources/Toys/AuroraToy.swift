import CoreGraphics
import Foundation

/// Slow curtains of light over a star field. The calm one.
final class AuroraToy: PixelToy {
    override var title: String { "Aurora" }
    override var emoji: String { "🌌" }
    override var pixelHeight: Int { 30 }

    private struct Curtain { var speed: Double, scale: Double, hue: Double, height: Double, phase: Double }

    private var curtains: [Curtain] = []
    private var stars: [(x: Int, y: Int, b: Double, tw: Double)] = []
    /// hsv() per pixel per curtain was the whole cost; bake each curtain's
    /// gradient into a small ramp instead.
    private var ramps: [[UInt32]] = []
    private var noise: [[Double]] = []
    private var t = 0.0
    private var rng = RNG(seed: 0xA47A)

    override func resized(to buf: PixelBuffer) {
        curtains = (0..<4).map { i in
            Curtain(speed: rng.range(0.05, 0.20), scale: rng.range(0.006, 0.030),
                    hue: 0.30 + Double(i) * 0.055 + rng.range(-0.02, 0.02),
                    height: rng.range(0.26, 0.55), phase: rng.range(0, 6.28))
        }
        ramps = curtains.map { c in
            (0..<32).map { hsv(c.hue + Double($0) / 32 * 0.12, 0.75, 1.0) }
        }
        // vertical striations, so each curtain reads as rays rather than a slab
        noise = curtains.map { c in
            (0..<buf.width).map { x in
                let v = sin(Double(x) * 0.21 + c.phase) * 0.5
                      + sin(Double(x) * 0.073 + c.phase * 2) * 0.5
                return 0.35 + 0.65 * max(0, v + 0.45)
            }
        }
        stars = (0..<70).map { _ in
            (x: rng.int(buf.width), y: rng.int(buf.height * 2 / 3),
             b: rng.range(0.25, 1.0), tw: rng.range(0, 6.28))
        }
    }

    override func tap(at p: CGPoint, size: CGSize) {
        for i in curtains.indices { curtains[i].phase += 1.3 }
    }

    override func update(dt: Double, size: CGSize) { t += dt }

    override func renderPixels(into buf: PixelBuffer) {
        for y in 0..<buf.height {
            let f = Double(y) / Double(buf.height)
            buf.fill(0, y, buf.width, 1, rgb(Int(4 + 8 * f), Int(5 + 10 * f), Int(14 + 20 * f)))
        }
        for s in stars {
            let tw = 0.6 + 0.4 * sin(t * 1.6 + s.tw)
            let v = Int(200 * s.b * tw)
            buf.blend(s.x, s.y, rgb(v, v, min(255, v + 30)), 0.9)
        }
        for (ci, c) in curtains.enumerated() {
            let ramp = ramps[ci]
            for x in 0..<buf.width {
                let n = sin(Double(x) * c.scale + t * c.speed * 6 + c.phase)
                      + 0.5 * sin(Double(x) * c.scale * 2.7 - t * c.speed * 4)
                let topF = 0.04 + 0.46 * (n + 1.5) / 3
                let top = Int(topF * Double(buf.height))
                let bottom = min(buf.height, top + Int(c.height * Double(buf.height)))
                guard bottom > top else { continue }
                let span = Double(bottom - top)
                for y in top..<bottom {
                    let f = Double(y - top) / span
                    let a = (1 - f) * (1 - f) * 0.46 * noise[ci][x]
                    buf.blend(x, y, ramp[min(31, Int(f * 32))], a)
                }
            }
        }
    }
}
