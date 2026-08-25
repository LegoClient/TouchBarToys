import CoreGraphics
import Darwin
import Foundation

/// Scrolling throughput graph straight off the interface counters:
/// download above the axis, upload below.
final class NetworkToy: Toy {
    let title = "Network"
    let emoji = "📡"

    private var down: [Double] = []
    private var up: [Double] = []
    private var since = 0.0
    private var peak = 64_000.0
    private let samples = 220
    private let stats = SystemStats.shared
    private var rateIn: Double { stats.netIn }
    private var rateOut: Double { stats.netOut }

    init() {
        down = [Double](repeating: 0, count: samples)
        up = down
    }

    func update(dt: Double, size: CGSize) {
        stats.tick(dt: dt)
        since += dt
        guard since >= 0.35 else { return }
        since = 0
        down.append(rateIn); if down.count > samples { down.removeFirst() }
        up.append(rateOut); if up.count > samples { up.removeFirst() }
        let observed = max(down.max() ?? 0, up.max() ?? 0)
        // let the scale fall back slowly so a burst doesn't flatten it forever
        peak = max(64_000, max(observed, peak * 0.97))
    }

    func draw(in ctx: CGContext, size: CGSize) {
        ctx.setFillColor(CGColor(gray: 0.03, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))

        let labelW: CGFloat = 92
        let x0 = labelW
        let mid = size.height / 2
        let usable = size.width - x0 - 4
        let slot = usable / CGFloat(samples)

        ctx.setFillColor(CGColor(gray: 0.22, alpha: 1))
        ctx.fill(CGRect(x: x0, y: mid - 0.5, width: usable, height: 1))

        for i in 0..<samples {
            let x = x0 + CGFloat(i) * slot
            let dh = CGFloat(min(1, down[i] / peak)) * (mid - 2)
            let uh = CGFloat(min(1, up[i] / peak)) * (mid - 2)
            ctx.setFillColor(CGColor(red: 0.32, green: 0.72, blue: 1.0, alpha: 1))
            ctx.fill(CGRect(x: x, y: mid, width: max(1, slot - 0.4), height: dh))
            ctx.setFillColor(CGColor(red: 1.0, green: 0.55, blue: 0.28, alpha: 1))
            ctx.fill(CGRect(x: x, y: mid - uh, width: max(1, slot - 0.4), height: uh))
        }

        Text.draw("\u{2193} \(Self.rate(rateIn))", in: ctx, at: CGPoint(x: 8, y: mid + 2),
                  size: 9, color: CGColor(red: 0.32, green: 0.72, blue: 1.0, alpha: 1))
        Text.draw("\u{2191} \(Self.rate(rateOut))", in: ctx, at: CGPoint(x: 8, y: mid - 10),
                  size: 9, color: CGColor(red: 1.0, green: 0.55, blue: 0.28, alpha: 1))
    }

    private static func rate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond > 1_000_000 { return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000) }
        if bytesPerSecond > 1_000 { return String(format: "%.0f KB/s", bytesPerSecond / 1_000) }
        return String(format: "%.0f B/s", bytesPerSecond)
    }
}
