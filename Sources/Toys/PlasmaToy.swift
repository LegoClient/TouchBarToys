import CoreGraphics
import Foundation

/// Sine-field plasma. The cheapest flash per line of code there is.
final class PlasmaToy: PixelToy {
    override var title: String { "Plasma" }
    override var emoji: String { "🎨" }
    override var pixelHeight: Int { 30 }

    private var sinLUT = [Double](repeating: 0, count: 1024)
    private var xTerm: [Double] = []
    private var yTerm: [Double] = []
    private var t = 0.0
    private var palette = 0

    override init() {
        super.init()
        for i in 0..<1024 { sinLUT[i] = sin(Double(i) / 1024 * 2 * .pi) }
    }

    @inline(__always) private func fsin(_ x: Double) -> Double {
        sinLUT[Int(x * 162.97) & 1023]
    }

    override func resized(to buf: PixelBuffer) {
        xTerm = (0..<buf.width).map { fsin(Double($0) * 0.055) }
        yTerm = (0..<buf.height).map { fsin(Double($0) * 0.17) }
    }

    override func tap(at p: CGPoint, size: CGSize) { palette = (palette + 1) % 3 }

    override func update(dt: Double, size: CGSize) {
        _ = buffer(for: size)
        t += dt
    }

    override func renderPixels(into buf: PixelBuffer) {
        let t1 = t * 0.9, t2 = t * 1.35
        for y in 0..<buf.height {
            let yv = yTerm[y] + fsin(Double(y) * 0.09 + t2)
            let row = y * buf.width
            for x in 0..<buf.width {
                let v = xTerm[x]
                    + yv
                    + fsin((Double(x) + Double(y)) * 0.04 + t1)
                    + fsin((Double(x) * 0.03 + Double(y) * 0.11) + t2)
                let n = (v + 4) / 8            // 0...1
                switch palette {
                case 0: buf.data[row + x] = hsv(n + t * 0.05, 0.75, 1.0)
                case 1: buf.data[row + x] = rgb(Int(128 + 127 * fsin(n * 6.28 + t)),
                                                Int(40 + 40 * n),
                                                Int(128 + 127 * fsin(n * 6.28 + 2 + t)))
                default:
                    let g = Int(40 + 215 * n)
                    buf.data[row + x] = rgb(g / 4, g, Int(120 + 80 * n))
                }
            }
        }
    }
}
