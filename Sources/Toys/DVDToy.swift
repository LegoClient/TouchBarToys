import CoreGraphics
import Foundation

/// The screensaver. Everyone is waiting for the corner. It counts them.
final class DVDToy: Toy {
    let title = "DVD Bounce"
    let emoji = "💿"

    private let logoW: CGFloat = 44
    private let logoH: CGFloat = 20

    private var pos = CGPoint(x: 120, y: 6)
    private var vel = CGPoint(x: 132, y: 47)
    private var colorIndex = 0
    private var corners = 0
    private var flash: Double = 0
    private var lastXBounce: Double = -99
    private var lastYBounce: Double = -99
    private var t: Double = 0
    private var seeded = false

    private let palette: [CGColor] = [
        CGColor(red: 1.00, green: 0.25, blue: 0.35, alpha: 1),
        CGColor(red: 1.00, green: 0.62, blue: 0.11, alpha: 1),
        CGColor(red: 0.98, green: 0.95, blue: 0.20, alpha: 1),
        CGColor(red: 0.25, green: 0.95, blue: 0.45, alpha: 1),
        CGColor(red: 0.20, green: 0.75, blue: 1.00, alpha: 1),
        CGColor(red: 0.65, green: 0.40, blue: 1.00, alpha: 1),
        CGColor(red: 1.00, green: 0.40, blue: 0.85, alpha: 1),
    ]

    func tap(at p: CGPoint, size: CGSize) {
        // Nudge it toward the nearest corner, because waiting is agony.
        vel.x = vel.x < 0 ? -abs(vel.x) : abs(vel.x)
        pos = p
        colorIndex = (colorIndex + 1) % palette.count
    }

    func update(dt: Double, size: CGSize) {
        t += dt
        flash = max(0, flash - dt)
        if !seeded, size.width > 1 {
            seeded = true
            pos = CGPoint(x: size.width * 0.3, y: (size.height - logoH) / 2)
        }
        pos.x += vel.x * CGFloat(dt)
        pos.y += vel.y * CGFloat(dt)

        var hitX = false, hitY = false
        if pos.x <= 0 { pos.x = 0; vel.x = abs(vel.x); hitX = true }
        if pos.x + logoW >= size.width { pos.x = size.width - logoW; vel.x = -abs(vel.x); hitX = true }
        if pos.y <= 0 { pos.y = 0; vel.y = abs(vel.y); hitY = true }
        if pos.y + logoH >= size.height { pos.y = size.height - logoH; vel.y = -abs(vel.y); hitY = true }

        if hitX { lastXBounce = t }
        if hitY { lastYBounce = t }
        if hitX || hitY { colorIndex = (colorIndex + 1) % palette.count }
        // A "corner" is both axes bouncing within a few frames of each other.
        if hitX || hitY, abs(lastXBounce - lastYBounce) < 0.10, t - max(lastXBounce, lastYBounce) < 0.001 {
            corners += 1
            flash = 0.7
            lastXBounce = -99; lastYBounce = -99
        }
    }

    func draw(in ctx: CGContext, size: CGSize) {
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))

        let flashing = flash > 0 && Int(flash * 18) % 2 == 0
        let color = flashing ? CGColor(gray: 1, alpha: 1) : palette[colorIndex]

        Text.draw("CORNERS \(corners)", in: ctx, at: CGPoint(x: 8, y: 11),
                  size: 9, color: CGColor(gray: 0.42, alpha: 1))

        let cx = pos.x + logoW / 2
        let cy = pos.y + logoH / 2

        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(1.6)
        // the swoosh oval
        ctx.strokeEllipse(in: CGRect(x: pos.x, y: cy - 3.5, width: logoW, height: 15))
        // "DVD"
        Text.draw("DVD", in: ctx, at: CGPoint(x: cx, y: cy - 0.5),
                  size: 11, color: color, align: .center)
        // the little VIDEO plate
        let plate = CGRect(x: cx - 11, y: pos.y - 1, width: 22, height: 5.5)
        ctx.fill(plate)
        Text.draw("VIDEO", in: ctx, at: CGPoint(x: cx, y: pos.y + 0.4),
                  size: 4.2, color: CGColor(gray: 0, alpha: 1), align: .center)
        ctx.restoreGState()

        if flashing {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
