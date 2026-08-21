import CoreGraphics
import Foundation

/// Green glyph rain. Wide and short, so it reads as a shimmering wall.
final class MatrixToy: PixelToy {
    override var title: String { "Matrix Rain" }
    override var emoji: String { "🟩" }
    override var pixelHeight: Int { 30 }

    private let colW = 4          // 3px glyph + 1px gutter
    private let rowH = 6          // 5px glyph + 1px leading

    private struct Column {
        var head: Double          // row index of the bright leading glyph
        var speed: Double         // rows per second
        var tail: Int
        var glyphs: [Character]
        var jitter: Double        // seconds until the next glyph reshuffle
    }

    private var cols: [Column] = []
    private var rows = 5
    private var rng = RNG(seed: 0x1337_BEEF)

    override func resized(to buf: PixelBuffer) {
        rows = max(1, buf.height / rowH)
        let n = max(1, buf.width / colW)
        cols = (0..<n).map { _ in newColumn(startAbove: true) }
    }

    private func newColumn(startAbove: Bool) -> Column {
        let tail = 3 + rng.int(6)
        return Column(
            head: startAbove ? rng.range(-Double(rows) * 1.5, Double(rows)) : -Double(tail),
            speed: rng.range(3.5, 13.0),
            tail: tail,
            glyphs: (0..<(rows + 2)).map { _ in MicroFont.alphabet[rng.int(MicroFont.alphabet.count)] },
            jitter: rng.range(0.05, 0.4))
    }

    override func update(dt: Double, size: CGSize) {
        for i in cols.indices {
            cols[i].head += cols[i].speed * dt
            cols[i].jitter -= dt
            if cols[i].jitter <= 0 {
                cols[i].jitter = rng.range(0.05, 0.4)
                let k = rng.int(cols[i].glyphs.count)
                cols[i].glyphs[k] = MicroFont.alphabet[rng.int(MicroFont.alphabet.count)]
            }
            if cols[i].head - Double(cols[i].tail) > Double(rows) {
                cols[i] = newColumn(startAbove: false)
            }
        }
    }

    override func renderPixels(into buf: PixelBuffer) {
        buf.clear(rgb(0, 6, 0))
        for (ci, col) in cols.enumerated() {
            let x = ci * colW
            let head = Int(col.head)
            for k in 0...col.tail {
                let r = head - k
                guard r >= 0, r < rows else { continue }
                let color: UInt32
                if k == 0 {
                    color = rgb(210, 255, 210)          // bright leading glyph
                } else {
                    let f = 1.0 - Double(k) / Double(col.tail + 1)
                    color = rgb(0, Int(60 + 195 * f * f), Int(30 * f))
                }
                MicroFont.draw(col.glyphs[r % col.glyphs.count],
                               into: buf, x: x, y: r * rowH, color: color)
            }
        }
    }
}
