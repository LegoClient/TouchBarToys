import CoreGraphics
import Foundation

/// A tank of fish. Tap to sprinkle food; they'll come for it.
final class AquariumToy: PixelToy {
    override var title: String { "Aquarium" }
    override var emoji: String { "🐠" }
    override var pixelHeight: Int { 24 }

    private struct Fish {
        var x: Double, y: Double, vx: Double, size: Int, hue: Double, wiggle: Double
    }

    private var fish: [Fish] = []
    private var bubbles: [(x: Double, y: Double, r: Double)] = []
    private var food: [(x: Double, y: Double)] = []
    private var weeds: [(x: Int, h: Int, phase: Double)] = []
    private var w = 0, h = 0
    private var t = 0.0
    private var rng = RNG(seed: 0xF1CE)

    override func resized(to buf: PixelBuffer) {
        w = buf.width; h = buf.height
        fish = (0..<11).map { _ in newFish() }
        weeds = (0..<max(3, w / 90)).map { _ in
            (x: rng.int(w), h: 5 + rng.int(8), phase: rng.range(0, 6))
        }
        bubbles = (0..<14).map { _ in
            (x: rng.range(0, Double(w)), y: rng.range(0, Double(h)), r: rng.range(0.6, 1.8))
        }
    }

    private func newFish() -> Fish {
        let right = rng.d() < 0.5
        return Fish(x: rng.range(0, Double(w)), y: rng.range(4, Double(max(6, h - 6))),
                    vx: (right ? 1 : -1) * rng.range(11, 26),
                    size: 2 + rng.int(2), hue: rng.d(), wiggle: rng.range(0, 6))
    }

    override func tap(at p: CGPoint, size: CGSize) {
        guard w > 0, size.width > 0 else { return }
        let x = Double(p.x / size.width * CGFloat(w))
        for _ in 0..<5 {
            food.append((x: x + rng.range(-6, 6), y: 0))
        }
    }

    override func update(dt: Double, size: CGSize) {
        _ = buffer(for: size)
        t += dt

        for i in food.indices { food[i].y += 7 * dt }
        food.removeAll { $0.y > Double(h) - 2 }

        for i in fish.indices {
            // head for the nearest pellet, otherwise just cruise
            if let target = food.min(by: { abs($0.x - fish[i].x) < abs($1.x - fish[i].x) }),
               abs(target.x - fish[i].x) < Double(w) * 0.35 {
                fish[i].vx += (target.x > fish[i].x ? 26 : -26) * dt
                fish[i].y += (target.y > fish[i].y ? 9 : -9) * dt
            } else {
                fish[i].y += sin(t * 0.7 + fish[i].wiggle) * 3 * dt
            }
            fish[i].vx = max(-40, min(40, fish[i].vx))
            fish[i].x += fish[i].vx * dt
            fish[i].y = max(3, min(Double(h) - 4, fish[i].y))
            if fish[i].x < -14 { fish[i].x = Double(w) + 8 }
            if fish[i].x > Double(w) + 14 { fish[i].x = -8 }
        }
        food.removeAll { pellet in
            fish.contains { abs($0.x - pellet.x) < 3 && abs($0.y - pellet.y) < 3 }
        }

        for i in bubbles.indices {
            bubbles[i].y -= (7 + bubbles[i].r * 4) * dt
            if bubbles[i].y < -2 {
                bubbles[i].y = Double(h) + rng.range(0, 6)
                bubbles[i].x = rng.range(0, Double(w))
            }
        }
    }

    override func renderPixels(into buf: PixelBuffer) {
        for y in 0..<buf.height {
            let f = Double(y) / Double(buf.height)
            buf.fill(0, y, buf.width, 1, rgb(Int(8 + 10 * f), Int(46 + 30 * f), Int(84 + 40 * f)))
        }
        let floorY = buf.height - 3
        buf.fill(0, floorY, buf.width, 3, rgb(190, 170, 120))

        for weed in weeds {
            for k in 0..<weed.h {
                let sway = Int(sin(t * 1.3 + weed.phase + Double(k) * 0.4) * 2)
                buf.px(weed.x + sway, floorY - k, rgb(40, 130, 70))
                buf.px(weed.x + sway + 1, floorY - k, rgb(52, 156, 84))
            }
        }
        for b in bubbles {
            buf.blend(Int(b.x), Int(b.y), rgb(210, 235, 255), 0.5)
            if b.r > 1.2 { buf.blend(Int(b.x) + 1, Int(b.y), rgb(210, 235, 255), 0.3) }
        }
        for pellet in food {
            buf.px(Int(pellet.x), Int(pellet.y), rgb(220, 160, 70))
        }
        for f in fish { draw(f, into: buf) }
    }

    private func draw(_ f: Fish, into b: PixelBuffer) {
        let x = Int(f.x), y = Int(f.y)
        let dir = f.vx >= 0 ? 1 : -1
        let body = hsv(f.hue, 0.8, 1.0)
        let belly = hsv(f.hue, 0.45, 1.0)
        let s = f.size + 1
        // tapered body: full height in the middle, narrowing toward the nose
        for k in 0..<(s * 2) {
            let f2 = Double(k) / Double(s * 2 - 1)
            let taper = 1.0 - abs(f2 - 0.35) * 1.25
            let hgt = max(1, Int(Double(s) * taper))
            let col = x - s + (dir > 0 ? k : (s * 2 - 1 - k))
            b.fill(col, y - hgt / 2, 1, hgt, body)
        }
        b.fill(x - s + 1, y + s / 2 - 1, s * 2 - 2, 1, belly)
        // tail, flicking
        let flick = Int(sin(t * 9 + f.wiggle) * 1.6)
        let tx = x - dir * s
        for k in 0..<3 {
            b.fill(tx - dir * k, y + flick - k, 1, 1 + k * 2, body)
        }
        b.px(x + dir * (s - 2), y - 1, rgb(10, 10, 16))     // eye
    }
}
