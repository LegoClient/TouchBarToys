import CoreGraphics
import Foundation

/// The Doom PSX fire algorithm, stretched across the whole bar.
/// Tap anywhere to dump extra fuel under your finger.
final class FireToy: PixelToy {
    override var title: String { "Doom Fire" }
    override var emoji: String { "🔥" }
    override var pixelHeight: Int { 24 }

    private static let palette: [UInt32] = {
        let raw: [(Int, Int, Int)] = [
            (0x00, 0x00, 0x00), (0x1F, 0x07, 0x07), (0x2F, 0x0F, 0x07), (0x47, 0x0F, 0x07),
            (0x57, 0x17, 0x07), (0x67, 0x1F, 0x07), (0x77, 0x1F, 0x07), (0x8F, 0x27, 0x07),
            (0x9F, 0x2F, 0x07), (0xAF, 0x3F, 0x07), (0xBF, 0x47, 0x07), (0xC7, 0x47, 0x07),
            (0xDF, 0x4F, 0x07), (0xDF, 0x57, 0x07), (0xDF, 0x57, 0x07), (0xD7, 0x5F, 0x07),
            (0xD7, 0x5F, 0x07), (0xD7, 0x67, 0x0F), (0xCF, 0x6F, 0x0F), (0xCF, 0x77, 0x0F),
            (0xCF, 0x7F, 0x0F), (0xCF, 0x87, 0x17), (0xC7, 0x87, 0x17), (0xC7, 0x8F, 0x17),
            (0xC7, 0x97, 0x1F), (0xBF, 0x9F, 0x1F), (0xBF, 0x9F, 0x1F), (0xBF, 0xA7, 0x27),
            (0xBF, 0xA7, 0x27), (0xBF, 0xAF, 0x2F), (0xB7, 0xAF, 0x2F), (0xB7, 0xB7, 0x2F),
            (0xB7, 0xB7, 0x37), (0xCF, 0xCF, 0x6F), (0xDF, 0xDF, 0x9F), (0xEF, 0xEF, 0xC7),
            (0xFF, 0xFF, 0xFF),
        ]
        return raw.map { rgb($0.0, $0.1, $0.2) }
    }()

    private var heat: [UInt8] = []
    private var w = 0, h = 0
    private var rng = RNG(seed: 0xF12E)
    private var pokes: [(x: Int, life: Double)] = []
    private var accum: Double = 0

    override func resized(to buf: PixelBuffer) {
        w = buf.width; h = buf.height
        heat = [UInt8](repeating: 0, count: w * h)
        for x in 0..<w { heat[(h - 1) * w + x] = 36 }
    }

    override func tap(at p: CGPoint, size: CGSize) {
        guard size.width > 0, w > 0 else { return }
        let x = Int(p.x / size.width * CGFloat(w))
        pokes.append((x: x, life: 0.55))
    }

    override func update(dt: Double, size: CGSize) {
        _ = buffer(for: size)          // make sure heat[] matches the canvas
        accum += dt
        let stepDuration = 1.0 / 30.0
        var steps = 0
        while accum >= stepDuration && steps < 3 { accum -= stepDuration; steps += 1; step() }
        for i in pokes.indices { pokes[i].life -= dt }
        pokes.removeAll { $0.life <= 0 }
    }

    private func step() {
        guard w > 0, h > 1 else { return }
        // Keep the bottom row white-hot, plus a slow flicker so it breathes.
        for x in 0..<w {
            heat[(h - 1) * w + x] = rng.d() < 0.03 ? 30 : 36
        }
        // Extra fuel where the user tapped.
        for poke in pokes {
            for dx in -14...14 {
                let x = poke.x + dx
                guard x >= 0, x < w else { continue }
                heat[(h - 1) * w + x] = 36
                if h > 3 { heat[(h - 2) * w + x] = 36 }
            }
        }
        for x in 0..<w {
            for y in 1..<h {
                let src = y * w + x
                let pixel = heat[src]
                if pixel == 0 {
                    heat[src - w] = 0
                    continue
                }
                // Decay 0...3 per row: over a 24px bar that averages 1.5/row,
                // so heat 36 at the base reaches 0 right at the top.
                let decay = UInt8(rng.int(4))
                let wind = rng.int(3) - 1
                let dstX = x + wind
                guard dstX >= 0, dstX < w else { continue }
                heat[(y - 1) * w + dstX] = pixel > decay ? pixel - decay : 0
            }
        }
    }

    override func renderPixels(into buf: PixelBuffer) {
        guard heat.count == w * h else { return }
        let pal = FireToy.palette
        for i in 0..<(w * h) {
            buf.data[i] = pal[Int(heat[i])]
        }
    }
}
