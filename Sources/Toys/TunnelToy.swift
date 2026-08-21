import CoreGraphics
import Foundation

/// A row of tunnel mouths rather than one tunnel stretched across the bar.
/// Each mouth is normalised against the bar's height, so it stays round —
/// stretching a single radial tunnel to 33:1 is what made it look smeared.
final class TunnelToy: PixelToy {
    override var title: String { "Tunnels" }
    override var emoji: String { "🕳️" }
    override var pixelHeight: Int { 30 }

    private var angleLUT: [UInt8] = []
    private var depthLUT: [UInt8] = []
    private var shadeLUT: [UInt8] = []
    private var cellLUT: [UInt8] = []
    private var t: Double = 0
    private var palette = 0

    override func resized(to buf: PixelBuffer) {
        let w = buf.width, h = buf.height
        let count = w * h
        angleLUT = [UInt8](repeating: 0, count: count)
        depthLUT = [UInt8](repeating: 0, count: count)
        shadeLUT = [UInt8](repeating: 0, count: count)
        cellLUT = [UInt8](repeating: 0, count: count)

        let cy = Double(h) / 2
        // one mouth per ~2.4 bar-heights of width
        let n = max(1, Int((Double(w) / (Double(h) * 2.4)).rounded()))
        let cellW = Double(w) / Double(n)

        for y in 0..<h {
            let dy = (Double(y) - cy) / cy
            for x in 0..<w {
                let cell = min(n - 1, Int(Double(x) / cellW))
                let localCx = (Double(cell) + 0.5) * cellW
                // both axes divided by the same number of pixels, so it's round
                let dx = (Double(x) - localCx) / cy
                let r = max(0.03, (dx * dx + dy * dy).squareRoot())
                let a = (atan2(dy, dx) + .pi) / (2 * .pi)
                let i = y * w + x
                angleLUT[i] = UInt8(Int(a * 256) & 255)
                depthLUT[i] = UInt8(Int(42.0 / r) & 255)
                // dark down the throat, bright at the mouth, falling away in
                // the gaps so each tunnel reads as its own object
                let near = min(1.0, r * 2.2)
                let far = 1.0 / (1.0 + max(0.0, r - 0.9) * 1.15)
                shadeLUT[i] = UInt8(min(255.0, near * far * 255.0))
                cellLUT[i] = UInt8(cell & 255)
            }
        }
    }

    override func tap(at p: CGPoint, size: CGSize) { palette = (palette + 1) % 3 }

    override func update(dt: Double, size: CGSize) {
        _ = buffer(for: size)
        t += dt
    }

    override func renderPixels(into buf: PixelBuffer) {
        guard angleLUT.count == buf.width * buf.height else { return }
        let spin = Int(t * 26)
        let fly = Int(t * 90)
        for i in 0..<(buf.width * buf.height) {
            // offset each mouth so the row doesn't move as one block
            let cell = Int(cellLUT[i])
            let a = (Int(angleLUT[i]) &+ spin &+ cell &* 37) & 255
            let d = (Int(depthLUT[i]) &+ fly &+ cell &* 53) & 255
            let checker = ((a >> 5) ^ (d >> 5)) & 1
            let shade = Double(shadeLUT[i]) / 255.0
            let v = (checker == 1 ? 1.0 : 0.32) * shade
            switch palette {
            case 0: buf.data[i] = rgb(Int(70 * v), Int(230 * v), Int(255 * v))
            case 1: buf.data[i] = rgb(Int(255 * v), Int(90 * v), Int(200 * v))
            default: buf.data[i] = rgb(Int(255 * v), Int(190 * v), Int(60 * v))
            }
        }
    }
}
