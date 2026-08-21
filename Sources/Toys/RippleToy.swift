import CoreGraphics
import Foundation

/// Water over a tiled pool floor. The wave field refracts the floor beneath it
/// rather than just shading a flat blue, which is what made the old version
/// read as noise.
final class RippleToy: PixelToy {
    override var title: String { "Ripples" }
    override var emoji: String { "💧" }
    override var pixelHeight: Int { 30 }

    private var cur: [Float] = []
    private var prev: [Float] = []
    private var floorTex: [UInt32] = []
    private var w = 0, h = 0
    private var acc = 0.0
    private var idle = 0.0
    private var rng = RNG(seed: 0x8A20)

    override func resized(to buf: PixelBuffer) {
        w = buf.width; h = buf.height
        cur = [Float](repeating: 0, count: w * h)
        prev = cur
        buildFloor()
    }

    /// A pool floor: blue tiles, lighter grout, slight per-tile variation.
    private func buildFloor() {
        floorTex = [UInt32](repeating: 0, count: w * h)
        let tile = 9
        var tint = RNG(seed: 0x7113)
        for y in 0..<h {
            for x in 0..<w {
                let gx = x % tile, gy = y % tile
                let onGrout = gx == 0 || gy == 0
                let cell = (x / tile) &* 31 &+ (y / tile) &* 17
                let jitter = Double((cell &* 2654435761) % 23) / 23.0 * 0.18
                let depth = Double(y) / Double(h)
                var r = 18.0 + 26 * jitter
                var g = 92.0 + 46 * jitter - 24 * depth
                var b = 138.0 + 52 * jitter - 26 * depth
                if onGrout { r += 42; g += 48; b += 40 }
                floorTex[y * w + x] = rgb(Int(r), Int(g), Int(b))
                _ = tint.d()
            }
        }
    }

    override func tap(at p: CGPoint, size: CGSize) {
        guard w > 0, size.width > 0, size.height > 0 else { return }
        drop(Int(p.x / size.width * CGFloat(w)),
             Int((1 - p.y / size.height) * CGFloat(h)), 300)
        idle = 0
    }

    private func drop(_ x: Int, _ y: Int, _ power: Float) {
        for dy in -2...2 {
            for dx in -2...2 {
                let px = x + dx, py = y + dy
                guard px > 0, px < w - 1, py > 0, py < h - 1 else { continue }
                cur[py * w + px] = power
            }
        }
    }

    override func update(dt: Double, size: CGSize) {
        _ = buffer(for: size)
        idle += dt
        if idle > 1.9 {
            idle = 0
            drop(1 + rng.int(max(1, w - 2)), 1 + rng.int(max(1, h - 2)), 190)
        }
        acc += dt
        while acc >= 1.0 / 40.0 { acc -= 1.0 / 40.0; step() }
    }

    private func step() {
        guard w > 2, h > 2 else { return }
        for y in 1..<(h - 1) {
            let row = y * w
            for x in 1..<(w - 1) {
                let i = row + x
                let sum = cur[i - 1] + cur[i + 1] + cur[i - w] + cur[i + w]
                prev[i] = (sum / 2 - prev[i]) * 0.976
            }
        }
        swap(&cur, &prev)
    }

    override func renderPixels(into buf: PixelBuffer) {
        guard w > 2, h > 2, floorTex.count == w * h else { return }
        buf.clear(rgb(6, 26, 52))
        for y in 1..<(h - 1) {
            let row = y * w
            for x in 1..<(w - 1) {
                let i = row + x
                // surface gradient displaces where we sample the floor
                let gx = cur[i - 1] - cur[i + 1]
                let gy = cur[i - w] - cur[i + w]
                let sx = min(w - 1, max(0, x + Int(gx * 0.05)))
                let sy = min(h - 1, max(0, y + Int(gy * 0.05)))
                var c = floorTex[sy * w + sx]

                // steep slopes catch the light
                let lift = Double(gx) * 0.010
                if lift != 0 {
                    let r = min(255, max(0, Int(Double((c >> 16) & 255) + 150 * lift)))
                    let g = min(255, max(0, Int(Double((c >> 8) & 255) + 150 * lift)))
                    let b = min(255, max(0, Int(Double(c & 255) + 140 * lift)))
                    c = rgb(r, g, b)
                }
                buf.data[i] = c
                // specular glint on the sharpest crests
                if gx > 55 { buf.blend(x, y, rgb(255, 255, 255), min(0.8, Double(gx) / 340)) }
            }
        }
    }
}
