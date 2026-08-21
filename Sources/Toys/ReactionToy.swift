import CoreGraphics
import Foundation

/// Reaction timer. Tap to arm, wait for green, tap as fast as you can.
/// Tapping early counts against you.
final class ReactionToy: PixelToy {
    override var title: String { "Reaction Timer" }
    override var emoji: String { "⏱️" }
    override var pixelHeight: Int { 30 }

    private enum Phase { case idle, arming, go, result, tooSoon }

    private var phase: Phase = .idle
    private var timer = 0.0
    private var elapsed = 0.0
    private var last = 0
    private var best = 0
    private var rng = RNG(seed: 0x8EAC)

    override func tap(at p: CGPoint, size: CGSize) {
        switch phase {
        case .idle, .result, .tooSoon:
            phase = .arming
            timer = rng.range(1.2, 3.8)
        case .arming:
            phase = .tooSoon
        case .go:
            last = Int(elapsed * 1000)
            best = best == 0 ? last : min(best, last)
            phase = .result
        }
    }

    override func update(dt: Double, size: CGSize) {
        switch phase {
        case .arming:
            timer -= dt
            if timer <= 0 { phase = .go; elapsed = 0 }
        case .go:
            elapsed += dt
            if elapsed > 3 { phase = .idle }     // gave up
        default: break
        }
    }

    override func renderPixels(into buf: PixelBuffer) {
        let bg: UInt32
        let message: String
        switch phase {
        case .idle:    bg = rgb(28, 32, 44);  message = "TAP TO START"
        case .arming:  bg = rgb(168, 36, 32); message = "WAIT FOR GREEN"
        case .go:      bg = rgb(30, 176, 74); message = "TAP NOW"
        case .tooSoon: bg = rgb(190, 120, 20); message = "TOO SOON - TAP"
        case .result:  bg = rgb(28, 32, 44);  message = "\(last) MS - TAP"
        }
        buf.clear(bg)

        // a subtle sweep so the idle states aren't dead flat
        if phase == .arming || phase == .idle {
            for x in 0..<buf.width {
                let f = Double((x + Int(elapsed * 60)) % buf.width) / Double(buf.width)
                if f < 0.06 {
                    for y in 0..<buf.height { buf.blend(x, y, rgb(255, 255, 255), 0.05) }
                }
            }
        }

        let mid = buf.height / 2 - MicroFont.glyphH / 2
        let x = buf.width / 2 - MicroFont.width(message) / 2
        MicroFont.draw(message, into: buf, x: x + 1, y: mid + 1, color: rgb(0, 0, 0))
        MicroFont.draw(message, into: buf, x: x, y: mid, color: rgb(255, 255, 255))

        if best > 0 {
            let b = "BEST \(best)"
            MicroFont.draw(b, into: buf, x: 4, y: 2, color: rgb(210, 214, 220))
        }
    }
}
