import CoreGraphics
import Foundation

/// Every System scene at once: clock, CPU, memory, disk, network and battery,
/// each in its own panel across the bar.
final class DashboardToy: Toy {
    let title = "System Dashboard"
    let emoji = "🖥️"

    private let stats = SystemStats.shared
    private var bars: [Double] = []
    private var netHistory: [(down: Double, up: Double)] = []
    private var netPeak = 64_000.0
    private var sinceNetPush = 0.0

    private let netSamples = 46

    init() {
        netHistory = Array(repeating: (down: 0, up: 0), count: netSamples)
    }

    func update(dt: Double, size: CGSize) {
        stats.tick(dt: dt)

        // smooth the per-core bars: fast attack, slow decay
        if bars.count != stats.coreLoads.count {
            bars = stats.coreLoads
        }
        for i in bars.indices where i < stats.coreLoads.count {
            let target = stats.coreLoads[i]
            let rate = target > bars[i] ? 13.0 : 4.0
            bars[i] += (target - bars[i]) * min(1, rate * dt)
        }

        sinceNetPush += dt
        if sinceNetPush >= 0.25 {
            sinceNetPush = 0
            netHistory.append((down: stats.netIn, up: stats.netOut))
            if netHistory.count > netSamples { netHistory.removeFirst() }
            let observed = netHistory.map { max($0.down, $0.up) }.max() ?? 0
            netPeak = max(64_000, max(observed, netPeak * 0.985))
        }
    }

    func draw(in ctx: CGContext, size: CGSize) {
        ctx.setFillColor(CGColor(gray: 0.02, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))

        let pad: CGFloat = 4
        let gap: CGFloat = 5
        // the two fixed panels scale a little with the bar so they don't
        // crowd everything else on the narrower, button-mode canvas
        let clockW = min(96, max(64, size.width * 0.095))
        let battW = min(98, max(68, size.width * 0.098))
        let flexible = size.width - pad * 2 - gap * 5 - clockW - battW
        guard flexible > 80 else { return }

        var x = pad
        func advance(_ w: CGFloat) -> CGRect {
            let r = CGRect(x: x, y: 2, width: w, height: size.height - 4)
            x += w + gap
            return r
        }

        let panels = [
            advance(clockW), advance(flexible * 0.34), advance(flexible * 0.28),
            advance(flexible * 0.22), advance(flexible * 0.16), advance(battW),
        ]
        for r in panels { card(ctx, r) }

        clock(ctx, panels[0])
        cpu(ctx, panels[1])
        network(ctx, panels[2])
        memory(ctx, panels[3])
        disk(ctx, panels[4])
        battery(ctx, panels[5])
    }

    // MARK: - Panel furniture

    private func card(_ ctx: CGContext, _ r: CGRect) {
        ctx.setFillColor(CGColor(gray: 0.085, alpha: 1))
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.fillPath()
    }

    /// Label on the left, value on the right, graphic area returned. The label
    /// is dropped when the pair won't fit, so a long value can't collide with
    /// it on a narrow bar.
    private func header(_ ctx: CGContext, _ r: CGRect,
                        _ label: String, _ value: String, _ color: CGColor) -> CGRect {
        let inner = r.insetBy(dx: 6, dy: 0)
        let baseline = r.maxY - 9
        let valueW = Text.width(value, size: 7.5)
        if Text.width(label, size: 7) + valueW + 7 <= inner.width {
            Text.draw(label, in: ctx, at: CGPoint(x: inner.minX, y: baseline),
                      size: 7, color: CGColor(gray: 0.44, alpha: 1))
        }
        Text.draw(value, in: ctx, at: CGPoint(x: inner.maxX, y: baseline),
                  size: 7.5, color: color, align: .right)
        return CGRect(x: inner.minX, y: r.minY + 4, width: inner.width, height: r.height - 15)
    }

    private func capsule(_ ctx: CGContext, _ r: CGRect, _ color: CGColor) {
        guard r.width > 0.5, r.height > 0 else { return }
        let radius = min(r.height, r.width) / 2
        ctx.setFillColor(color)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius,
                           transform: nil))
        ctx.fillPath()
    }

    // MARK: - Panels

    private func clock(_ ctx: CGContext, _ r: CGRect) {
        let now = Date()
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: now)
        let time = String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)

        let df = DateFormatter()
        df.dateFormat = "EEE d MMM"
        let date = df.string(from: now).uppercased()
        let inner = r.insetBy(dx: 5, dy: 0)
        // only if it actually fits; otherwise the time gets the whole card
        let showDate = Text.width(date, size: 6.5) <= inner.width
        if showDate {
            Text.draw(date, in: ctx, at: CGPoint(x: r.midX, y: r.maxY - 9),
                      size: 6.5, color: CGColor(gray: 0.44, alpha: 1), align: .center)
        }

        var timeSize: CGFloat = showDate ? 12 : 14
        while Text.width(time, size: timeSize) > inner.width, timeSize > 8 { timeSize -= 0.5 }
        Text.draw(time, in: ctx, at: CGPoint(x: r.midX, y: r.minY + (showDate ? 6 : 9)),
                  size: timeSize, color: CGColor(gray: 0.95, alpha: 1), align: .center)

        let frac = CGFloat(Double(c.second ?? 0) / 60)
        let track = CGRect(x: inner.minX, y: r.minY + 3, width: inner.width, height: 2)
        capsule(ctx, track, CGColor(gray: 0.16, alpha: 1))
        capsule(ctx, CGRect(x: track.minX, y: track.minY,
                            width: max(2, track.width * frac), height: track.height),
                CGColor(red: 0.45, green: 0.68, blue: 1.0, alpha: 1))
    }

    private func cpu(_ ctx: CGContext, _ r: CGRect) {
        let pct = Int((stats.cpuTotal * 100).rounded())
        let area = header(ctx, r, "CPU", "\(pct)%", heat(stats.cpuTotal))
        guard !bars.isEmpty, area.width > 4, area.height > 1 else { return }

        // A dozen cores across a 260pt panel would be 20pt-wide slabs, so
        // interpolate up to a denser spectrum instead.
        let count = max(bars.count, min(52, Int(area.width / 5)))
        let slot = area.width / CGFloat(count)
        let barW = max(1.5, slot - 1.6)
        // never taller than the graphic area, whatever the bar width
        let floor = min(barW, area.height)
        for i in 0..<count {
            let f = Double(i) / Double(max(1, count - 1)) * Double(bars.count - 1)
            let a = bars[Int(f)]
            let b = bars[min(bars.count - 1, Int(f) + 1)]
            let v = a + (b - a) * (f - f.rounded(.down))
            let x = area.minX + CGFloat(i) * slot
            capsule(ctx, CGRect(x: x, y: area.minY, width: barW, height: area.height),
                    CGColor(gray: 0.15, alpha: 1))
            let h = max(floor, min(area.height, CGFloat(v) * area.height))
            capsule(ctx, CGRect(x: x, y: area.minY, width: barW, height: h), heat(v))
        }
    }

    private func network(_ ctx: CGContext, _ r: CGRect) {
        let value = "\u{2193}\(SystemStats.rate(stats.netIn)) \u{2191}\(SystemStats.rate(stats.netOut))"
        let area = header(ctx, r, "NET", value, CGColor(gray: 0.74, alpha: 1))
        let mid = area.midY
        ctx.setFillColor(CGColor(gray: 0.16, alpha: 1))
        ctx.fill(CGRect(x: area.minX, y: mid - 0.5, width: area.width, height: 1))
        let slot = area.width / CGFloat(netSamples)
        let half = area.height / 2 - 0.5
        for (i, s) in netHistory.enumerated() {
            let x = area.minX + CGFloat(i) * slot
            let w = max(1, slot - 0.5)
            let dh = CGFloat(min(1, s.down / netPeak)) * half
            let uh = CGFloat(min(1, s.up / netPeak)) * half
            if dh > 0.3 {
                capsule(ctx, CGRect(x: x, y: mid, width: w, height: dh),
                        CGColor(red: 0.32, green: 0.72, blue: 1.0, alpha: 1))
            }
            if uh > 0.3 {
                capsule(ctx, CGRect(x: x, y: mid - uh, width: w, height: uh),
                        CGColor(red: 1.0, green: 0.55, blue: 0.28, alpha: 1))
            }
        }
    }

    private func memory(_ ctx: CGContext, _ r: CGRect) {
        let used = stats.wired + stats.active + stats.compressed
        let area = header(ctx, r, "RAM", String(format: "%.1fG", used / 1_073_741_824),
                          CGColor(gray: 0.84, alpha: 1))
        guard stats.totalRAM > 0 else { return }
        capsule(ctx, area, CGColor(gray: 0.16, alpha: 1))
        // one clipped capsule, filled in segments, so the ends stay rounded
        ctx.saveGState()
        let radius = area.height / 2
        ctx.addPath(CGPath(roundedRect: area, cornerWidth: radius, cornerHeight: radius,
                           transform: nil))
        ctx.clip()
        var x = area.minX
        for (bytes, color) in [
            (stats.wired, CGColor(red: 1.0, green: 0.42, blue: 0.38, alpha: 1)),
            (stats.active, CGColor(red: 0.42, green: 0.78, blue: 1.0, alpha: 1)),
            (stats.compressed, CGColor(red: 1.0, green: 0.75, blue: 0.30, alpha: 1)),
        ] {
            let w = area.width * CGFloat(bytes / stats.totalRAM)
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: x, y: area.minY, width: w, height: area.height))
            x += w
        }
        ctx.restoreGState()
    }

    private func disk(_ ctx: CGContext, _ r: CGRect) {
        let freeGB = (stats.diskTotal - stats.diskUsed) / 1_000_000_000
        let frac = stats.diskTotal > 0 ? stats.diskUsed / stats.diskTotal : 0
        let area = header(ctx, r, "DISK", String(format: "%.0fG", freeGB),
                          CGColor(gray: 0.84, alpha: 1))
        capsule(ctx, area, CGColor(gray: 0.16, alpha: 1))
        capsule(ctx, CGRect(x: area.minX, y: area.minY,
                            width: max(area.height, area.width * CGFloat(frac)),
                            height: area.height),
                frac > 0.9 ? CGColor(red: 1.0, green: 0.35, blue: 0.3, alpha: 1)
                           : CGColor(red: 0.55, green: 0.85, blue: 0.55, alpha: 1))
    }

    private func battery(_ ctx: CGContext, _ r: CGRect) {
        let pct = Int((stats.batteryLevel * 100).rounded())
        let color: CGColor
        if stats.charging || stats.plugged {
            color = CGColor(red: 0.24, green: 0.85, blue: 0.36, alpha: 1)
        } else if stats.batteryLevel < 0.15 {
            color = CGColor(red: 1.0, green: 0.30, blue: 0.25, alpha: 1)
        } else {
            color = CGColor(gray: 0.88, alpha: 1)
        }
        // percentage always; time remaining only when there is room for it
        var value = "\(pct)%"
        if stats.batteryMinutes > 0 {
            let withTime = value + String(format: " %d:%02d", stats.batteryMinutes / 60,
                                          stats.batteryMinutes % 60)
            if Text.width(withTime, size: 7.5) + 12 <= r.width { value = withTime }
        }
        let area = header(ctx, r, "BATT", value, color)

        let body = CGRect(x: area.minX, y: area.minY, width: area.width - 3.5,
                          height: area.height)
        ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 1))
        ctx.setLineWidth(1)
        let radius = body.height / 3
        ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 0.5, dy: 0.5),
                           cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.strokePath()
        capsule(ctx, CGRect(x: body.maxX + 1, y: body.midY - 1.8, width: 2.5, height: 3.6),
                CGColor(gray: 0.5, alpha: 1))
        let inner = body.insetBy(dx: 2, dy: 2)
        capsule(ctx, CGRect(x: inner.minX, y: inner.minY,
                            width: max(inner.height, inner.width * CGFloat(stats.batteryLevel)),
                            height: inner.height), color)
        if stats.charging {
            ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
            ctx.beginPath()
            let c = CGPoint(x: body.midX, y: body.midY)
            ctx.move(to: CGPoint(x: c.x + 1.1, y: c.y + 3.4))
            ctx.addLine(to: CGPoint(x: c.x - 2.3, y: c.y - 0.3))
            ctx.addLine(to: CGPoint(x: c.x - 0.2, y: c.y - 0.3))
            ctx.addLine(to: CGPoint(x: c.x - 1.2, y: c.y - 3.4))
            ctx.addLine(to: CGPoint(x: c.x + 2.3, y: c.y + 0.5))
            ctx.addLine(to: CGPoint(x: c.x + 0.2, y: c.y + 0.5))
            ctx.closePath()
            ctx.fillPath()
        }
    }

    private func heat(_ v: Double) -> CGColor {
        let c = min(1, max(0, v))
        return CGColor(red: min(1.0, c * 2.1), green: min(1.0, (1 - c) * 1.9 + 0.15),
                       blue: 0.18, alpha: 1)
    }
}
