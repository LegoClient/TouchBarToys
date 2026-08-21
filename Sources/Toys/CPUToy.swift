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
    private var coreLoads: [Double] = []
    private var previous: [(busy: Double, total: Double)] = []
    private var sinceSample: Double = 1
    private var rng = RNG(seed: 0xC9FF)
    private var total: Double = 0
    private var clock: Double = 0

    init() {
        levels = [Double](repeating: 0, count: barCount)
        peaks = [Double](repeating: 0, count: barCount)
    }

    func update(dt: Double, size: CGSize) {
        clock += dt
        sinceSample += dt
        if sinceSample >= 0.35 { sinceSample = 0; sample() }

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
            // fast attack, slow decay — proper VU behaviour
            let rate = target > levels[i] ? 14.0 : 4.0
            levels[i] += (target - levels[i]) * min(1, rate * dt)
            peaks[i] = max(peaks[i] - dt * 0.42, levels[i])
        }
    }

    private func sample() {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                 &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: UnsafeMutableRawPointer(info))),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let n = Int(count)
        var loads = [Double](repeating: 0, count: n)
        var snapshot = [(busy: Double, total: Double)]()
        for i in 0..<n {
            let base = i * Int(CPU_STATE_MAX)
            let user = Double(info[base + Int(CPU_STATE_USER)])
            let sys  = Double(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = Double(info[base + Int(CPU_STATE_NICE)])
            let idle = Double(info[base + Int(CPU_STATE_IDLE)])
            let busy = user + sys + nice
            let tot = busy + idle
            snapshot.append((busy: busy, total: tot))
            if previous.count == n {
                let db = busy - previous[i].busy
                let dt = tot - previous[i].total
                loads[i] = dt > 0 ? max(0, min(1, db / dt)) : 0
            }
        }
        previous = snapshot
        if !loads.isEmpty { coreLoads = loads }
        total = coreLoads.isEmpty ? 0 : coreLoads.reduce(0, +) / Double(coreLoads.count)
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
