import CoreGraphics
import Foundation

/// A pop-tart cat leaving a rainbow behind it. Original pixel art, same idea.
final class NyanToy: PixelToy {
    override var title: String { "Rainbow Pop-Tart Cat" }
    override var emoji: String { "🌈" }
    override var pixelHeight: Int { 20 }

    private let bg      = rgb(0, 51, 102)
    private let ink     = rgb(0, 0, 0)
    private let tart    = rgb(255, 158, 196)
    private let crust   = rgb(255, 205, 225)
    private let sprinkle = rgb(255, 240, 248)
    private let fur     = rgb(158, 158, 158)
    private let furDark = rgb(120, 120, 120)
    private let cheek   = rgb(255, 133, 180)
    private let white   = rgb(255, 255, 255)

    private let bands = [rgb(255, 0, 0), rgb(255, 153, 0), rgb(255, 255, 0),
                         rgb(51, 255, 0), rgb(0, 153, 255), rgb(102, 51, 255)]

    private var t: Double = 0
    private var scroll: Double = 0
    private var stars: [(x: Double, y: Int, phase: Double, speed: Double)] = []
    private var rng = RNG(seed: 0xCA7)

    override func resized(to buf: PixelBuffer) {
        stars = (0..<16).map { _ in
            (x: rng.range(0, Double(buf.width)),
             y: rng.int(buf.height),
             phase: rng.range(0, 6),
             speed: rng.range(26, 46))
        }
    }

    override func update(dt: Double, size: CGSize) {
        t += dt
        scroll += dt * 34
    }

    override func renderPixels(into buf: PixelBuffer) {
        buf.clear(bg)

        // --- twinkling starfield -------------------------------------------
        for i in stars.indices {
            stars[i].x -= stars[i].speed * (1.0 / 60.0) * 2
            if stars[i].x < -3 {
                stars[i].x = Double(buf.width) + rng.range(0, 20)
                stars[i].y = rng.int(buf.height)
                stars[i].speed = rng.range(26, 46)
            }
            let f = Int(t * 9 + stars[i].phase) % 6
            star(buf, Int(stars[i].x), stars[i].y, f)
        }

        // --- rainbow --------------------------------------------------------
        let catX = Int(Double(buf.width) * 0.78)
        let bandH = 2
        let top = buf.height / 2 - (bands.count * bandH) / 2
        let phase = Int(scroll)
        for x in 0..<min(catX + 4, buf.width) {
            // square-wave wobble, 4px blocks, 2px amplitude
            let blk = Int(floor(Double(x + phase) / 4.0))
            let off = (blk % 2 == 0) ? 0 : 2
            for (i, c) in bands.enumerated() {
                buf.fill(x, top + off + i * bandH, 1, bandH, c)
            }
        }

        // --- the cat --------------------------------------------------------
        let frame = Int(t * 11) % 6
        let bob = [0, 0, 1, 1, 1, 0][frame]
        cat(buf, catX, 1 + bob, frame)
    }

    // MARK: pixel art

    private func star(_ b: PixelBuffer, _ x: Int, _ y: Int, _ f: Int) {
        switch f {
        case 0, 5:
            b.px(x, y, white)
        case 1, 4:
            b.px(x, y, white); b.px(x - 1, y, white); b.px(x + 1, y, white)
            b.px(x, y - 1, white); b.px(x, y + 1, white)
        default:
            b.px(x - 2, y, white); b.px(x + 2, y, white)
            b.px(x, y - 2, white); b.px(x, y + 2, white)
            b.px(x - 1, y, white); b.px(x + 1, y, white)
            b.px(x, y - 1, white); b.px(x, y + 1, white)
        }
    }

    /// `x` = left edge of the pop-tart, `y` = top of the sprite box (16 tall).
    private func cat(_ b: PixelBuffer, _ x: Int, _ y: Int, _ f: Int) {
        // tail — swings up and down behind the tart
        let tailY = [7, 6, 5, 5, 6, 7][f]
        b.box(x - 5, y + tailY, 6, 3, fill: fur, stroke: ink)

        // legs — little stubs that paddle
        let legDrop = [0, 1, 1, 0, 0, 1][f]
        for (i, lx) in [1, 5, 9, 12].enumerated() {
            let d = (i % 2 == 0) ? legDrop : 1 - legDrop
            b.box(x + lx, y + 12 + d, 3, 4, fill: fur, stroke: ink)
        }

        // pop-tart body
        b.box(x, y + 2, 16, 12, fill: crust, stroke: ink)
        b.fill(x + 2, y + 4, 12, 8, tart)
        for (sx, sy) in [(3, 5), (8, 4), (5, 8), (10, 9), (4, 10), (11, 6), (7, 6)] {
            b.px(x + sx, y + sy, sprinkle)
        }

        // head
        let hx = x + 13
        b.box(hx, y + 3, 11, 11, fill: fur, stroke: ink)
        // ears
        b.px(hx + 2, y + 1, ink); b.px(hx + 3, y + 1, ink)
        b.px(hx + 2, y + 2, fur); b.px(hx + 3, y + 2, fur)
        b.px(hx + 7, y + 1, ink); b.px(hx + 8, y + 1, ink)
        b.px(hx + 7, y + 2, fur); b.px(hx + 8, y + 2, fur)
        // eyes
        for ex in [hx + 3, hx + 7] {
            b.fill(ex, y + 6, 2, 3, ink)
            b.px(ex, y + 6, white)
        }
        // cheeks
        b.fill(hx + 1, y + 10, 2, 2, cheek)
        b.fill(hx + 8, y + 10, 2, 2, cheek)
        // mouth  ( ˘ ³˘ )
        b.px(hx + 5, y + 10, ink)
        b.fill(hx + 4, y + 11, 3, 1, ink)
        b.px(hx + 3, y + 10, ink)
        b.px(hx + 7, y + 10, ink)
        // a touch of shading under the chin so the head reads as round
        b.px(hx + 1, y + 4, furDark); b.px(hx + 9, y + 4, furDark)
        b.px(hx + 1, y + 12, furDark); b.px(hx + 9, y + 12, furDark)
    }
}
