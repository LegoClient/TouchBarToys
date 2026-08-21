import CoreGraphics
import Foundation

/// Forty-odd oscillators at slightly different frequencies. They drift out of
/// phase into chaos and then snap back into a wave. Tap to re-sync them.
final class PendulumWaveToy: Toy {
    let title = "Pendulum Wave"
    let emoji = "〰️"

    private let count = 44
    private let baseFreq = 0.25
    private let deltaFreq = 0.030
    private var t: Double = 0

    func tap(at p: CGPoint, size: CGSize) { t = 0 }

    func update(dt: Double, size: CGSize) { t += dt }

    func draw(in ctx: CGContext, size: CGSize) {
        ctx.setFillColor(CGColor(gray: 0.02, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))

        let mid = size.height / 2
        let amp = size.height / 2 - 4
        let slot = size.width / CGFloat(count + 1)

        for i in 0..<count {
            let x = slot * CGFloat(i + 1)
            let f = baseFreq + Double(i) * deltaFreq
            let phase = 2 * Double.pi * f * t
            let y = mid + amp * CGFloat(sin(phase))

            // hue sweeps along the bar so the wave reads as a moving rainbow
            let hue = CGFloat(i) / CGFloat(count)
            let color = NSColorLike(hue: hue, saturation: 0.75, brightness: 1.0)

            ctx.setFillColor(CGColor(gray: 1, alpha: 0.06))
            ctx.fill(CGRect(x: x - 0.5, y: 2, width: 1, height: size.height - 4))

            ctx.setFillColor(color)
            ctx.fillEllipse(in: CGRect(x: x - 2.2, y: y - 2.2, width: 4.4, height: 4.4))
            ctx.setFillColor(CGColor(red: color.components?[0] ?? 1,
                                     green: color.components?[1] ?? 1,
                                     blue: color.components?[2] ?? 1, alpha: 0.25))
            ctx.fillEllipse(in: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))
        }
    }
}

/// Small HSB -> CGColor helper so the toys don't have to import AppKit.
func NSColorLike(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> CGColor {
    let h = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
    let i = Int(h)
    let f = h - CGFloat(i)
    let p = brightness * (1 - saturation)
    let q = brightness * (1 - saturation * f)
    let t = brightness * (1 - saturation * (1 - f))
    let (r, g, b): (CGFloat, CGFloat, CGFloat)
    switch i % 6 {
    case 0: (r, g, b) = (brightness, t, p)
    case 1: (r, g, b) = (q, brightness, p)
    case 2: (r, g, b) = (p, brightness, t)
    case 3: (r, g, b) = (p, q, brightness)
    case 4: (r, g, b) = (t, p, brightness)
    default: (r, g, b) = (brightness, p, q)
    }
    return CGColor(red: r, green: g, blue: b, alpha: 1)
}
