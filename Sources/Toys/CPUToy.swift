import CoreGraphics
import Darwin
import Foundation

/// A spectrum-analyser that is actually your CPU. Dumb, flashy, mildly useful.
final class CPUToy: Toy {
    let title = "CPU Spectrum"
    let emoji = "📊"

    private let barCount = 56
    private var levels: [Double]
    private var peaks: [Double]
    private var rng = RNG(seed: 0xC9FF)
    private var clock: Double = 0
    private let stats = SystemStats.shared
    private var coreLoads: [Double] { stats.coreLoads }
    private var total: Double { stats.cpuTotal }

    init() {
        levels = [Double](repeating: 0, count: barCount)
        peaks = [Double](repeating: 0, count: barCount)
    }

    func update(dt: Double, size: CGSize) {
        clock += dt
        stats.tick(dt: dt)

        for i in 0..<barCount {
            // map each bar onto a core, with a little per-bar noise so
            // neighbouring bars don't move as one solid block
            let target: Double
            if coreLoads.isEmpty {
                target = 0
            } else {
                let f = Double(i) / Double(barCount - 1) * Double(coreLoads.count - 1)
                let a = coreLoads[Int(f)]
                let b = coreLoads[min(coreLoads.count - 1, Int(f) + 1)]
                let mix = a + (b - a) * (f - f.rounded(.down))
                // idle shimmer so a quiet machine still looks alive
                let idle = 0.05 + 0.035 * sin(clock * 3.1 + Double(i) * 0.55)
                target = min(1, max(idle, mix * rng.range(0.72, 1.18) + 0.02))
            }
            // fast attack, slow decay, like a real VU meter
            let rate = target > levels[i] ? 14.0 : 4.0
            levels[i] += (target - levels[i]) * min(1, rate * dt)
            peaks[i] = max(peaks[i] - dt * 0.42, levels[i])
        }
    }

    func draw(in ctx: CGContext, size: CGSize) {
        ctx.setFillColor(CGColor(gray: 0.03, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))

        let labelW: CGFloat = 60
        let x0 = labelW
        let usable = size.width - x0 - 6
        let slot = usable / CGFloat(barCount)
        let barW = max(1, slot - 1.5)

        for i in 0..<barCount {
            let x = x0 + CGFloat(i) * slot
            let h = max(1.5, CGFloat(levels[i]) * (size.height - 4))
            ctx.setFillColor(colorFor(levels[i]))
            ctx.fill(CGRect(x: x, y: 2, width: barW, height: h))
            // peak-hold cap
            let py = 2 + CGFloat(peaks[i]) * (size.height - 4)
            ctx.setFillColor(CGColor(gray: 0.95, alpha: 0.85))
            ctx.fill(CGRect(x: x, y: min(py, size.height - 2), width: barW, height: 1.4))
        }

        let pct = Int((total * 100).rounded())
        Text.draw("CPU", in: ctx, at: CGPoint(x: 8, y: 17), size: 8,
                  color: CGColor(gray: 0.55, alpha: 1))
        Text.draw("\(pct)%", in: ctx, at: CGPoint(x: 8, y: 5), size: 10,
                  color: colorFor(total))
    }

    private func colorFor(_ v: Double) -> CGColor {
        // green -> yellow -> red
        let c = min(1, max(0, v))
        let r = min(1.0, c * 2.1)
        let g = min(1.0, (1 - c) * 1.9 + 0.15)
        return CGColor(red: r, green: g, blue: 0.18, alpha: 1)
    }
}
