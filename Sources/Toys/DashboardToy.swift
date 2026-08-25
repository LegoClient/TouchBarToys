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
        ctx.setFillColor(CGColor(gray: 0.03, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))

        let pad: CGFloat = 6
        let clockW: CGFloat = 76
        let battW: CGFloat = 82
        let sep: CGFloat = 9
        let flexible = size.width - clockW - battW - pad * 2 - sep * 5
        guard flexible > 60 else { return }

        var x = pad
        func advance(_ w: CGFloat) -> CGRect {
            let r = CGRect(x: x, y: 0, width: w, height: size.height)
            x += w + sep
            return r
        }

        let clockRect = advance(clockW)
        let cpuRect = advance(flexible * 0.34)
        let netRect = advance(flexible * 0.28)
        let ramRect = advance(flexible * 0.22)
        let diskRect = advance(flexible * 0.16)
        let battRect = advance(battW)

        for r in [clockRect, cpuRect, netRect, ramRect, diskRect] {
            ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
            ctx.fill(CGRect(x: r.maxX + sep / 2 - 0.5, y: 5, width: 1, height: size.height - 10))
        }

        clock(ctx, clockRect)
        cpu(ctx, cpuRect)
        network(ctx, netRect)
        memory(ctx, ramRect)
        disk(ctx, diskRect)
        battery(ctx, battRect)
    }

    // MARK: - Panels

    /// Draws the panel label and value, and returns the area left for a graphic.
    private func header(_ ctx: CGContext, _ r: CGRect,
                        _ label: String, _ value: String, _ color: CGColor) -> CGRect {
        Text.draw(label, in: ctx, at: CGPoint(x: r.minX, y: r.maxY - 9),
                  size: 7, color: CGColor(gray: 0.42, alpha: 1))
        Text.draw(value, in: ctx, at: CGPoint(x: r.maxX, y: r.maxY - 9),
                  size: 7.5, color: color, align: .right)
        return CGRect(x: r.minX, y: 3, width: r.width, height: r.height - 14)
    }

    private func clock(_ ctx: CGContext, _ r: CGRect) {
        let now = Date()
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: now)
        let time = String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        Text.draw(time, in: ctx, at: CGPoint(x: r.midX, y: r.midY - 3),
                  size: 13, color: CGColor(gray: 0.94, alpha: 1), align: .center)
        let df = DateFormatter()
        df.dateFormat = "EEE d MMM"
        Text.draw(df.string(from: now).uppercased(),
                  in: ctx, at: CGPoint(x: r.midX, y: r.maxY - 9),
                  size: 6.5, color: CGColor(gray: 0.42, alpha: 1), align: .center)
        // the minute ticking over
        let frac = CGFloat(Double(c.second ?? 0) / 60)
        ctx.setFillColor(CGColor(gray: 0.18, alpha: 1))
        ctx.fill(CGRect(x: r.minX, y: 3, width: r.width, height: 1.5))
        ctx.setFillColor(CGColor(red: 0.45, green: 0.68, blue: 1.0, alpha: 1))
        ctx.fill(CGRect(x: r.minX, y: 3, width: r.width * frac, height: 1.5))
    }

    private func cpu(_ ctx: CGContext, _ r: CGRect) {
        let pct = Int((stats.cpuTotal * 100).rounded())
        let area = header(ctx, r, "CPU", "\(pct)%", heat(stats.cpuTotal))
        guard !bars.isEmpty else { return }
        let slot = area.width / CGFloat(bars.count)
        for (i, v) in bars.enumerated() {
            let h = max(1.5, CGFloat(v) * area.height)
            ctx.setFillColor(heat(v))
            ctx.fill(CGRect(x: area.minX + CGFloat(i) * slot, y: area.minY,
                            width: max(1, slot - 1.4), height: h))
        }
    }

    private func network(_ ctx: CGContext, _ r: CGRect) {
        let value = "\u{2193}\(SystemStats.rate(stats.netIn)) \u{2191}\(SystemStats.rate(stats.netOut))"
        let area = header(ctx, r, "NET", value, CGColor(gray: 0.72, alpha: 1))
        let mid = area.midY
        ctx.setFillColor(CGColor(gray: 0.18, alpha: 1))
        ctx.fill(CGRect(x: area.minX, y: mid - 0.5, width: area.width, height: 1))
        let slot = area.width / CGFloat(netSamples)
        let half = area.height / 2 - 1
        for (i, s) in netHistory.enumerated() {
            let x = area.minX + CGFloat(i) * slot
            let w = max(1, slot - 0.4)
            let dh = CGFloat(min(1, s.down / netPeak)) * half
            let uh = CGFloat(min(1, s.up / netPeak)) * half
            ctx.setFillColor(CGColor(red: 0.32, green: 0.72, blue: 1.0, alpha: 1))
            ctx.fill(CGRect(x: x, y: mid, width: w, height: dh))
            ctx.setFillColor(CGColor(red: 1.0, green: 0.55, blue: 0.28, alpha: 1))
            ctx.fill(CGRect(x: x, y: mid - uh, width: w, height: uh))
        }
    }

    private func memory(_ ctx: CGContext, _ r: CGRect) {
        let used = stats.wired + stats.active + stats.compressed
        let gb = used / 1_073_741_824
        let area = header(ctx, r, "RAM", String(format: "%.1fG", gb),
                          CGColor(gray: 0.82, alpha: 1))
        guard stats.totalRAM > 0 else { return }
        ctx.setFillColor(CGColor(gray: 0.13, alpha: 1))
        ctx.fill(area)
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
    }

    private func disk(_ ctx: CGContext, _ r: CGRect) {
        let freeGB = (stats.diskTotal - stats.diskUsed) / 1_000_000_000
        let frac = stats.diskTotal > 0 ? stats.diskUsed / stats.diskTotal : 0
        let area = header(ctx, r, "DISK", String(format: "%.0fG", freeGB),
                          CGColor(gray: 0.82, alpha: 1))
        ctx.setFillColor(CGColor(gray: 0.13, alpha: 1))
        ctx.fill(area)
        ctx.setFillColor(frac > 0.9
                         ? CGColor(red: 1.0, green: 0.35, blue: 0.3, alpha: 1)
                         : CGColor(red: 0.55, green: 0.85, blue: 0.55, alpha: 1))
        ctx.fill(CGRect(x: area.minX, y: area.minY,
                        width: area.width * CGFloat(frac), height: area.height))
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
        // percentage first, with time remaining after it when known
        var value = "\(pct)%"
        if stats.batteryMinutes > 0 {
            value += String(format: " %d:%02d", stats.batteryMinutes / 60,
                            stats.batteryMinutes % 60)
        }
        let area = header(ctx, r, "BATT", value, color)

        // a battery outline with a nub, filled to the charge level
        let body = CGRect(x: area.minX, y: area.minY + 1,
                          width: area.width - 4, height: area.height - 2)
        ctx.setStrokeColor(CGColor(gray: 0.55, alpha: 1))
        ctx.setLineWidth(1)
        ctx.stroke(body.insetBy(dx: 0.5, dy: 0.5))
        ctx.setFillColor(CGColor(gray: 0.55, alpha: 1))
        ctx.fill(CGRect(x: body.maxX + 1, y: body.midY - 2.2, width: 2.5, height: 4.4))
        ctx.setFillColor(color)
        let inner = body.insetBy(dx: 2, dy: 2)
        ctx.fill(CGRect(x: inner.minX, y: inner.minY,
                        width: inner.width * CGFloat(stats.batteryLevel), height: inner.height))
        if stats.charging {
            ctx.setFillColor(CGColor(gray: 0.06, alpha: 1))
            ctx.beginPath()
            let c = CGPoint(x: body.midX, y: body.midY)
            ctx.move(to: CGPoint(x: c.x + 1.2, y: c.y + 4))
            ctx.addLine(to: CGPoint(x: c.x - 2.6, y: c.y - 0.4))
            ctx.addLine(to: CGPoint(x: c.x - 0.2, y: c.y - 0.4))
            ctx.addLine(to: CGPoint(x: c.x - 1.4, y: c.y - 4))
            ctx.addLine(to: CGPoint(x: c.x + 2.6, y: c.y + 0.6))
            ctx.addLine(to: CGPoint(x: c.x + 0.2, y: c.y + 0.6))
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
