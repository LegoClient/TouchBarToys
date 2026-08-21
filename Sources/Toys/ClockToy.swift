import CoreGraphics
import Foundation

/// Binary clock plus the time in plain digits. Tap to switch between binary,
/// big digits, and a bar that fills as the minute goes by.
final class ClockToy: Toy {
    let title = "Clock"
    let emoji = "🕰️"

    private enum Mode: Int, CaseIterable { case binary, big, sweep }
    private var mode: Mode = .binary
    private var t = 0.0

    func tap(at p: CGPoint, size: CGSize) {
        let all = Mode.allCases
        mode = all[(all.firstIndex(of: mode)! + 1) % all.count]
    }

    func update(dt: Double, size: CGSize) { t += dt }

    func draw(in ctx: CGContext, size: CGSize) {
        ctx.setFillColor(CGColor(gray: 0.03, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))

        let now = Date()
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: now)
        let hh = c.hour ?? 0, mm = c.minute ?? 0, ss = c.second ?? 0
        let sub = Double(c.nanosecond ?? 0) / 1_000_000_000

        switch mode {
        case .binary:
            let groups: [(String, Int, Int, CGColor)] = [
                ("H", hh, 5, CGColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1)),
                ("M", mm, 6, CGColor(red: 0.45, green: 0.85, blue: 0.45, alpha: 1)),
                ("S", ss, 6, CGColor(red: 0.45, green: 0.68, blue: 1.0, alpha: 1)),
            ]
            let dot: CGFloat = 4.4
            let gap: CGFloat = 2.2
            var x = size.width / 2 - 96
            for (label, value, bits, color) in groups {
                Text.draw(label, in: ctx, at: CGPoint(x: x, y: 3), size: 8,
                          color: CGColor(gray: 0.4, alpha: 1))
                for b in stride(from: bits - 1, through: 0, by: -1) {
                    let on = (value >> b) & 1 == 1
                    let y = size.height / 2 - dot / 2 + CGFloat(bits - 1 - b) * 0 + 4
                    ctx.setFillColor(on ? color : CGColor(gray: 0.16, alpha: 1))
                    ctx.fillEllipse(in: CGRect(x: x + 12 + CGFloat(bits - 1 - b) * (dot + gap),
                                               y: y, width: dot, height: dot))
                    // second row of dots below, so each group reads as a column pair
                    ctx.setFillColor(on ? color : CGColor(gray: 0.11, alpha: 1))
                    ctx.fillEllipse(in: CGRect(x: x + 12 + CGFloat(bits - 1 - b) * (dot + gap),
                                               y: y - dot - 1.6, width: dot, height: dot))
                }
                x += 12 + CGFloat(bits) * (dot + gap) + 18
            }
            let digits = String(format: "%02d:%02d:%02d", hh, mm, ss)
            Text.draw(digits, in: ctx, at: CGPoint(x: size.width - 14, y: size.height / 2 - 5),
                      size: 13, color: CGColor(gray: 0.85, alpha: 1), align: .right)

        case .big:
            let digits = String(format: "%02d:%02d:%02d", hh, mm, ss)
            Text.draw(digits, in: ctx, at: CGPoint(x: size.width / 2, y: size.height / 2 - 9),
                      size: 24, color: CGColor(gray: 0.93, alpha: 1), align: .center)
            let df = DateFormatter()
            df.dateFormat = "EEEE d MMMM"
            Text.draw(df.string(from: now).uppercased(),
                      in: ctx, at: CGPoint(x: 12, y: size.height / 2 - 4),
                      size: 9, color: CGColor(gray: 0.45, alpha: 1))

        case .sweep:
            let bars: [(String, Double, CGColor)] = [
                ("HOUR", (Double(hh % 12) + Double(mm) / 60) / 12,
                 CGColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1)),
                ("MIN", (Double(mm) + Double(ss) / 60) / 60,
                 CGColor(red: 0.45, green: 0.85, blue: 0.45, alpha: 1)),
                ("SEC", (Double(ss) + sub) / 60,
                 CGColor(red: 0.45, green: 0.68, blue: 1.0, alpha: 1)),
            ]
            let h = (size.height - 8) / 3
            for (i, bar) in bars.enumerated() {
                let y = size.height - 3 - CGFloat(i + 1) * h
                ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
                ctx.fill(CGRect(x: 46, y: y, width: size.width - 56, height: h - 1.5))
                ctx.setFillColor(bar.2)
                ctx.fill(CGRect(x: 46, y: y, width: (size.width - 56) * CGFloat(bar.1),
                                height: h - 1.5))
                Text.draw(bar.0, in: ctx, at: CGPoint(x: 8, y: y + 0.5), size: 7,
                          color: CGColor(gray: 0.5, alpha: 1))
            }
        }
    }
}
