import CoreGraphics
import Foundation

/// Elementary cellular automata. Each row is one generation and the display
/// scrolls upward, which is exactly the shape of this screen.
final class Rule110Toy: PixelToy {
    override var title: String { "Rule 110" }
    override var emoji: String { "🔺" }
    override var pixelHeight: Int { 30 }

    private let rules: [(name: String, bits: UInt8, hue: (Int, Int, Int))] = [
        ("110", 110, (120, 240, 255)), ("30", 30, (255, 170, 90)),
        ("90", 90, (170, 255, 140)), ("184", 184, (255, 130, 220)),
        ("54", 54, (255, 240, 140)),
    ]
    private var ruleIndex = 0
    private var cells: [UInt8] = []
    private var rows: [[UInt8]] = []
    private var acc = 0.0
    private var randomSeed = false

    override func resized(to buf: PixelBuffer) {
        cells = [UInt8](repeating: 0, count: buf.width)
        rows = []
        seed()
    }

    private func seed() {
        var rng = RNG(seed: 0x110 &+ UInt64(ruleIndex))
        for i in cells.indices {
            cells[i] = randomSeed ? (rng.d() < 0.5 ? 1 : 0) : 0
        }
        if !randomSeed, !cells.isEmpty { cells[cells.count / 2] = 1 }
        rows = [cells]
    }

    override func tap(at p: CGPoint, size: CGSize) {
        ruleIndex = (ruleIndex + 1) % rules.count
        if ruleIndex == 0 { randomSeed.toggle() }
        seed()
    }

    override func update(dt: Double, size: CGSize) {
        _ = buffer(for: size)
        acc += dt
        while acc >= 0.05 {
            acc -= 0.05
            step()
        }
    }

    private func step() {
        guard cells.count > 2 else { return }
        let bits = rules[ruleIndex].bits
        var next = cells
        let n = cells.count
        for i in 0..<n {
            let l = cells[(i + n - 1) % n]
            let c = cells[i]
            let r = cells[(i + 1) % n]
            let pattern = (l << 2) | (c << 1) | r
            next[i] = (bits >> pattern) & 1
        }
        cells = next
        rows.append(cells)
        if rows.count > pixelHeight { rows.removeFirst() }
    }

    override func renderPixels(into buf: PixelBuffer) {
        buf.clear(rgb(4, 4, 10))
        let (_, _, tint) = rules[ruleIndex]
        let count = rows.count
        for (i, row) in rows.enumerated() {
            // newest generation at the bottom, fading as it scrolls up
            let y = buf.height - (count - i)
            guard y >= 0, y < buf.height else { continue }
            let f = 0.35 + 0.65 * Double(i) / Double(max(1, count - 1))
            let c = rgb(Int(Double(tint.0) * f), Int(Double(tint.1) * f), Int(Double(tint.2) * f))
            for x in 0..<min(row.count, buf.width) where row[x] == 1 {
                buf.px(x, y, c)
            }
        }
        MicroFont.draw("RULE \(rules[ruleIndex].name)", into: buf, x: 3, y: 2, color: rgb(90, 90, 110))
    }
}
