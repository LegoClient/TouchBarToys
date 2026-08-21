import CoreGraphics
import Foundation

/// An endless zoom into the set, cropped to the strip. Rendered at low
/// resolution and scaled up, which keeps it cheap and pleasantly chunky.
final class MandelbrotToy: PixelToy {
    override var title: String { "Mandelbrot" }
    override var emoji: String { "🌀" }
    override var pixelHeight: Int { 20 }

    /// Points with long, interesting approaches.
    private let targets: [(Double, Double)] = [
        (-0.743643887037151, 0.131825904205330),
        (-0.16070135, 1.0375665),
        (0.360240443437614, -0.641313061064803),
        (-1.749705768080503, 0.000005879797808),
    ]
    private var targetIndex = 0
    private var zoom = 0.045
    private var t = 0.0
    private var maxIter = 64

    override func tap(at p: CGPoint, size: CGSize) {
        targetIndex = (targetIndex + 1) % targets.count
        zoom = 0.045
    }

    override func update(dt: Double, size: CGSize) {
        t += dt
        zoom *= 1 - 0.28 * dt
        if zoom < 1.2e-13 { zoom = 0.045; targetIndex = (targetIndex + 1) % targets.count }
        // more detail is needed the deeper it goes
        maxIter = min(190, 60 + Int(-log(zoom) * 9))
    }

    override func renderPixels(into buf: PixelBuffer) {
        let (cx, cy) = targets[targetIndex]
        let scale = zoom / Double(buf.width)
        let halfW = Double(buf.width) / 2, halfH = Double(buf.height) / 2
        for py in 0..<buf.height {
            let y0 = cy + (Double(py) - halfH) * scale
            let row = py * buf.width
            for px in 0..<buf.width {
                let x0 = cx + (Double(px) - halfW) * scale
                var x = 0.0, y = 0.0, x2 = 0.0, y2 = 0.0
                var i = 0
                while x2 + y2 <= 4 && i < maxIter {
                    y = 2 * x * y + y0
                    x = x2 - y2 + x0
                    x2 = x * x; y2 = y * y
                    i += 1
                }
                if i >= maxIter {
                    buf.data[row + px] = rgb(0, 0, 0)
                } else {
                    // smooth colouring, plus a slow palette cycle
                    let nu = Double(i) - log2(max(1e-9, log2(max(1e-9, x2 + y2)) / 2))
                    buf.data[row + px] = hsv(nu * 0.021 + t * 0.05, 0.72, 1.0)
                }
            }
        }
    }
}
