import CoreGraphics
import Foundation

/// Conway's Game of Life on a very wide, very short torus. Gliders crossing the
/// whole length are the whole point. Tap to drop one in.
final class LifeToy: PixelToy {
    override var title: String { "Game of Life" }
    override var emoji: String { "🦠" }
    override var pixelHeight: Int { 30 }

    private var w = 0, h = 0
    private var grid: [UInt8] = []
    private var age: [UInt8] = []
    private var acc = 0.0
    private var sinceReseed = 0.0
    private var rng = RNG(seed: 0x11FE)

    override func resized(to buf: PixelBuffer) {
        w = buf.width; h = buf.height
        reseed()
    }

    private func reseed() {
        grid = (0..<(w * h)).map { _ in rng.d() < 0.14 ? 1 : 0 }
        age = [UInt8](repeating: 0, count: w * h)
        sinceReseed = 0
    }

    override func tap(at p: CGPoint, size: CGSize) {
        guard w > 0, size.width > 0 else { return }
        let cx = Int(p.x / size.width * CGFloat(w))
        // a glider, pointed right
        let cy = h / 2
        for (dx, dy) in [(1, 0), (2, 1), (0, 2), (1, 2), (2, 2)] {
            let x = (cx + dx + w) % w, y = (cy + dy + h) % h
            grid[y * w + x] = 1
        }
    }

    override func update(dt: Double, size: CGSize) {
        _ = buffer(for: size)
        acc += dt
        sinceReseed += dt
        while acc >= 1.0 / 14.0 {
            acc -= 1.0 / 14.0
            step()
        }
        let alive = grid.reduce(0) { $0 + Int($1) }
        if alive < 12 || sinceReseed > 45 { reseed() }
    }

    private func step() {
        guard w > 2, h > 2 else { return }
        var next = grid
        for y in 0..<h {
            let yUp = ((y + h - 1) % h) * w
            let yMid = y * w
            let yDn = ((y + 1) % h) * w
            for x in 0..<w {
                let xl = (x + w - 1) % w, xr = (x + 1) % w
                let n = Int(grid[yUp + xl]) + Int(grid[yUp + x]) + Int(grid[yUp + xr])
                      + Int(grid[yMid + xl]) + Int(grid[yMid + xr])
                      + Int(grid[yDn + xl]) + Int(grid[yDn + x]) + Int(grid[yDn + xr])
                let alive = grid[yMid + x] == 1
                let lives = alive ? (n == 2 || n == 3) : (n == 3)
                next[yMid + x] = lives ? 1 : 0
                if lives {
                    age[yMid + x] = alive ? min(255, age[yMid + x] &+ 6) : 0
                } else {
                    age[yMid + x] = 0
                }
            }
        }
        grid = next
    }

    override func renderPixels(into buf: PixelBuffer) {
        buf.clear(rgb(3, 6, 10))
        for i in 0..<min(grid.count, buf.width * buf.height) where grid[i] == 1 {
            // young cells are hot white, settled ones cool to deep blue
            let a = Double(age[i]) / 255.0
            buf.data[i] = rgb(Int(255 - 190 * a), Int(255 - 110 * a), 255)
        }
    }
}
