import CoreGraphics
import Foundation

/// Falling-sand automaton. Drag a finger along the bar to pour; the grains
/// pile, slide and settle. Tap the far left to switch material.
final class SandToy: PixelToy {
    override var title: String { "Falling Sand" }
    override var emoji: String { "⏳" }
    override var pixelHeight: Int { 30 }

    private enum Cell: UInt8 { case empty = 0, sand, water, stone }

    private var grid: [UInt8] = []
    private var tint: [UInt8] = []          // hue index, so piles are rainbow-banded
    private var w = 0, h = 0
    private var material: Cell = .sand
    private var pour: (x: Int, life: Double)?
    private var hue = 0.0
    private var acc = 0.0
    private var idle = 0.0
    private var fullFor = 0.0
    private var rng = RNG(seed: 0x5A4D)

    override func resized(to buf: PixelBuffer) {
        w = buf.width; h = buf.height
        grid = [UInt8](repeating: 0, count: w * h)
        tint = [UInt8](repeating: 0, count: w * h)
    }

    override func tap(at p: CGPoint, size: CGSize) {
        guard w > 0, size.width > 0 else { return }
        let x = Int(p.x / size.width * CGFloat(w))
        if x < w / 24 {
            material = material == .sand ? .water : (material == .water ? .stone : .sand)
            return
        }
        pour = (x: x, life: 0.16)
        idle = 0
    }

    override func update(dt: Double, size: CGSize) {
        _ = buffer(for: size)
        hue += dt * 26
        idle += dt
        if idle > 1.4, pour == nil {
            idle = 0
            pour = (x: rng.int(max(1, w)), life: 0.5)
        }
        // Wipe only when a pile genuinely reaches the top and stays there.
        // Row 0 is where pouring happens, so test below the spout — checking
        // row 0 here meant every pour instantly cleared the grid.
        let probe = 4 * w
        let capped = probe + w <= grid.count
            && (0..<w).contains { grid[probe + $0] != 0 }
        fullFor = capped ? fullFor + dt : 0
        if fullFor > 1.5 {
            fullFor = 0
            grid = [UInt8](repeating: 0, count: w * h)
        }
        if var p = pour {
            for dx in -2...2 {
                let x = p.x + dx
                guard x >= 0, x < w else { continue }
                for dy in 0..<2 {
                    let i = dy * w + x
                    if grid[i] == 0 {
                        grid[i] = material.rawValue
                        tint[i] = UInt8(Int(hue) & 255)
                    }
                }
            }
            p.life -= dt
            pour = p.life > 0 ? p : nil
        }
        acc += dt
        while acc >= 1.0 / 45.0 { acc -= 1.0 / 45.0; step() }
    }

    private func step() {
        guard w > 2, h > 2 else { return }
        // bottom-up so a grain only moves once per tick
        for y in stride(from: h - 2, through: 0, by: -1) {
            let flip = rng.d() < 0.5
            for k in 0..<w {
                let x = flip ? k : w - 1 - k
                let i = y * w + x
                let cell = grid[i]
                guard cell == Cell.sand.rawValue || cell == Cell.water.rawValue else { continue }
                let below = (y + 1) * w + x
                if grid[below] == 0 { move(i, below); continue }
                // sand only slides diagonally; water also spreads sideways
                let dir = rng.d() < 0.5 ? -1 : 1
                for d in [dir, -dir] {
                    let nx = x + d
                    guard nx >= 0, nx < w else { continue }
                    if grid[(y + 1) * w + nx] == 0 { move(i, (y + 1) * w + nx); break }
                    if cell == Cell.water.rawValue, grid[y * w + nx] == 0 {
                        move(i, y * w + nx); break
                    }
                }
            }
        }
    }

    @inline(__always) private func move(_ from: Int, _ to: Int) {
        grid[to] = grid[from]; tint[to] = tint[from]
        grid[from] = 0
    }

    override func renderPixels(into buf: PixelBuffer) {
        buf.clear(rgb(8, 8, 12))
        for i in 0..<(w * h) {
            switch grid[i] {
            case Cell.sand.rawValue:
                let t = Double(tint[i]) / 255.0
                buf.data[i] = hsv(t, 0.70, 1.0)
            case Cell.water.rawValue:
                buf.data[i] = rgb(50, 130, 235)
            case Cell.stone.rawValue:
                buf.data[i] = rgb(122, 122, 132)
            default: break
            }
        }
        let name = material == .sand ? "SAND" : (material == .water ? "WATER" : "STONE")
        MicroFont.draw(name, into: buf, x: 3, y: 2, color: rgb(120, 120, 130))
    }
}

/// HSV -> packed RGB, for toys that want a hue sweep.
func hsv(_ h: Double, _ s: Double, _ v: Double) -> UInt32 {
    let hh = (h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
    let i = Int(hh)
    let f = hh - Double(i)
    let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
    let (r, g, b): (Double, Double, Double)
    switch i % 6 {
    case 0: (r, g, b) = (v, t, p)
    case 1: (r, g, b) = (q, v, p)
    case 2: (r, g, b) = (p, v, t)
    case 3: (r, g, b) = (p, q, v)
    case 4: (r, g, b) = (t, p, v)
    default: (r, g, b) = (v, p, q)
    }
    return rgb(Int(r * 255), Int(g * 255), Int(b * 255))
}
