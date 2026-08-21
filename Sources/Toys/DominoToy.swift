import CoreGraphics
import Foundation

/// A line of dominoes the length of the bar. Tap one and the topple runs
/// outward from it; once they're all down they stand back up in a wave.
final class DominoToy: PixelToy {
    override var title: String { "Dominoes" }
    override var emoji: String { "🎳" }
    override var pixelHeight: Int { 24 }

    private struct Piece { var angle: Double; var vel: Double; var hue: Double }

    private var pieces: [Piece] = []
    private var spacing = 9
    private var w = 0, h = 0
    private var restingFor = 0.0
    private var standing: Int? = nil          // index of the next one to stand back up
    private var rng = RNG(seed: 0xD0D0)

    override func resized(to buf: PixelBuffer) {
        w = buf.width; h = buf.height
        let n = max(4, (w - 16) / spacing)
        pieces = (0..<n).map { i in
            Piece(angle: 0, vel: 0, hue: Double(i) / Double(n))
        }
    }

    override func tap(at p: CGPoint, size: CGSize) {
        guard !pieces.isEmpty, size.width > 0 else { return }
        standing = nil
        let i = min(pieces.count - 1, max(0, Int(p.x / size.width * CGFloat(pieces.count))))
        if pieces[i].angle < 0.1 { pieces[i].vel = 3.4 }
    }

    override func update(dt: Double, size: CGSize) {
        _ = buffer(for: size)
        guard !pieces.isEmpty else { return }

        if let s = standing {
            // walk back along the line setting them upright again
            if s < pieces.count {
                pieces[s].angle = 0; pieces[s].vel = 0
                standing = s + 1
                restingFor = 0
            } else {
                standing = nil
            }
            return
        }

        var anyMoving = false
        for i in pieces.indices {
            guard pieces[i].vel != 0 || pieces[i].angle > 0 else { continue }
            if pieces[i].angle < .pi / 2 {
                anyMoving = true
                // gravity torque grows as it leans further over
                pieces[i].vel += (1.6 + 5.0 * sin(pieces[i].angle)) * dt
                pieces[i].angle += pieces[i].vel * dt
                // once it's leaned far enough it nudges the next one along
                if pieces[i].angle > 0.62, i + 1 < pieces.count,
                   pieces[i + 1].angle < 0.02, pieces[i + 1].vel == 0 {
                    pieces[i + 1].vel = max(1.6, pieces[i].vel * 0.85)
                }
            } else {
                pieces[i].angle = .pi / 2
                pieces[i].vel = 0
            }
        }

        let allDown = pieces.allSatisfy { $0.angle >= .pi / 2 - 0.01 }
        if allDown {
            restingFor += dt
            if restingFor > 1.2 { standing = 0 }
        } else if !anyMoving {
            restingFor += dt
            // nothing is moving and they're not all down: give it a nudge
            if restingFor > 3.0 {
                restingFor = 0
                pieces[0].vel = 3.4
            }
        }
    }

    override func renderPixels(into buf: PixelBuffer) {
        for y in 0..<buf.height {
            let f = Double(y) / Double(buf.height)
            buf.fill(0, y, buf.width, 1, rgb(Int(18 + 14 * f), Int(20 + 16 * f), Int(28 + 18 * f)))
        }
        let groundY = buf.height - 3
        buf.fill(0, groundY + 1, buf.width, 2, rgb(58, 50, 44))

        let pieceH = Double(groundY) - 4
        for (i, p) in pieces.enumerated() {
            let baseX = Double(8 + i * spacing)
            let tipX = baseX + sin(p.angle) * pieceH
            let tipY = Double(groundY) - cos(p.angle) * pieceH
            let color = hsv(p.hue, 0.55, p.angle >= .pi / 2 - 0.01 ? 0.55 : 1.0)
            thickLine(buf, baseX, Double(groundY), tipX, tipY, color, width: 3)
        }
    }

    private func thickLine(_ b: PixelBuffer, _ x0: Double, _ y0: Double,
                           _ x1: Double, _ y1: Double, _ c: UInt32, width: Int) {
        let steps = max(1, Int(max(abs(x1 - x0), abs(y1 - y0)) * 1.5))
        // perpendicular offset so the domino has thickness
        let dx = x1 - x0, dy = y1 - y0
        let len = max(0.001, (dx * dx + dy * dy).squareRoot())
        let px = -dy / len, py = dx / len
        for s in 0...steps {
            let f = Double(s) / Double(steps)
            let x = x0 + dx * f, y = y0 + dy * f
            for k in 0..<width {
                let o = Double(k) - Double(width - 1) / 2
                b.px(Int(x + px * o), Int(y + py * o), c)
            }
        }
    }
}
