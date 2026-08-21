import CoreGraphics
import Foundation

/// Lava-lamp blobs that merge and split. Field sums only, no square roots.
final class MetaballsToy: PixelToy {
    override var title: String { "Metaballs" }
    override var emoji: String { "🫧" }
    override var pixelHeight: Int { 30 }

    private struct Ball { var x: Double, y: Double, vx: Double, vy: Double, r: Double }

    private var balls: [Ball] = []
    private var w = 0, h = 0
    private var palette = 0
    private var rng = RNG(seed: 0xBA11)

    override func resized(to buf: PixelBuffer) {
        w = buf.width; h = buf.height
        balls = (0..<7).map { _ in
            Ball(x: rng.range(0, Double(w)), y: rng.range(0, Double(h)),
                 vx: rng.range(-34, 34), vy: rng.range(-11, 11),
                 r: rng.range(10, 17))
        }
    }

    override func tap(at p: CGPoint, size: CGSize) { palette = (palette + 1) % 3 }

    override func update(dt: Double, size: CGSize) {
        _ = buffer(for: size)
        for i in balls.indices {
            balls[i].x += balls[i].vx * dt
            balls[i].y += balls[i].vy * dt
            if balls[i].x < 0 { balls[i].x = 0; balls[i].vx = abs(balls[i].vx) }
            if balls[i].x > Double(w) { balls[i].x = Double(w); balls[i].vx = -abs(balls[i].vx) }
            if balls[i].y < 0 { balls[i].y = 0; balls[i].vy = abs(balls[i].vy) }
            if balls[i].y > Double(h) { balls[i].y = Double(h); balls[i].vy = -abs(balls[i].vy) }
        }
    }

    override func renderPixels(into buf: PixelBuffer) {
        for y in 0..<buf.height {
            let row = y * buf.width
            for x in 0..<buf.width {
                var field = 0.0
                for b in balls {
                    let dx = Double(x) - b.x, dy = (Double(y) - b.y) * 1.55
                    field += b.r * b.r / max(1.0, dx * dx + dy * dy)
                }
                let v = min(1.0, field * 1.15)
                let banded = v * v * (3 - 2 * v) / 1.0
                switch palette {
                case 0: buf.data[row + x] = rgb(Int(255 * banded), Int(90 * banded * banded), Int(30 * banded))
                case 1: buf.data[row + x] = rgb(Int(40 * banded), Int(210 * banded), Int(255 * banded * banded))
                default: buf.data[row + x] = hsv(0.75 + banded * 0.35, 0.8, banded)
                }
            }
        }
    }
}
