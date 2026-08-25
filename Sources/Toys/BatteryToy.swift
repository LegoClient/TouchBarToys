import CoreGraphics
import Foundation
import IOKit.ps

/// Charge as a full-width bar, with a charging shimmer and time remaining.
final class BatteryToy: Toy {
    let title = "Battery"
    let emoji = "🔋"

    private var t = 0.0
    private let stats = SystemStats.shared
    private var percent: Double { stats.batteryLevel }
    private var charging: Bool { stats.charging }
    private var plugged: Bool { stats.plugged }
    private var minutes: Int { stats.batteryMinutes }

    func update(dt: Double, size: CGSize) {
        t += dt
        stats.tick(dt: dt)
    }

    func draw(in ctx: CGContext, size: CGSize) {
        ctx.setFillColor(CGColor(gray: 0.04, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))

        let color: CGColor
        if charging || plugged {
            color = CGColor(red: 0.24, green: 0.85, blue: 0.36, alpha: 1)
        } else if percent < 0.12 {
            color = CGColor(red: 1.0, green: 0.25, blue: 0.22, alpha: 1)
        } else if percent < 0.25 {
            color = CGColor(red: 1.0, green: 0.68, blue: 0.15, alpha: 1)
        } else {
            color = CGColor(red: 0.85, green: 0.87, blue: 0.92, alpha: 1)
        }

        let inset: CGFloat = 3
        let track = CGRect(x: inset, y: inset, width: size.width - inset * 2,
                           height: size.height - inset * 2)
        ctx.setFillColor(CGColor(gray: 0.13, alpha: 1))
        ctx.addPath(CGPath(roundedRect: track, cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.fillPath()

        let fill = CGRect(x: track.minX, y: track.minY,
                          width: max(6, track.width * CGFloat(percent)), height: track.height)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: track, cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.clip()
        ctx.setFillColor(color)
        ctx.fill(fill)

        // a light sweeping along the fill while charging
        if charging {
            let sweep = CGFloat((t * 0.55).truncatingRemainder(dividingBy: 1)) * fill.width
            for i in 0..<26 {
                let x = sweep - CGFloat(i) * 2
                guard x >= 0, x < fill.width else { continue }
                ctx.setFillColor(CGColor(gray: 1, alpha: 0.05 * (1 - CGFloat(i) / 26)))
                ctx.fill(CGRect(x: x, y: track.minY, width: 2, height: track.height))
            }
        }
        ctx.restoreGState()

        let pct = "\(Int((percent * 100).rounded()))%"
        Text.draw(pct, in: ctx, at: CGPoint(x: 12, y: size.height / 2 - 5),
                  size: 13, color: CGColor(gray: 0.06, alpha: 1))

        var right = charging ? "CHARGING" : (plugged ? "PLUGGED IN" : "ON BATTERY")
        if minutes > 0 {
            right = String(format: "%@  %d:%02d", right, minutes / 60, minutes % 60)
        }
        Text.draw(right, in: ctx, at: CGPoint(x: size.width - 12, y: size.height / 2 - 4),
                  size: 10, color: CGColor(gray: 0.62, alpha: 1), align: .right)
    }
}
