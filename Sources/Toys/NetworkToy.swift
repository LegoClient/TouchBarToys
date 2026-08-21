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
    private var lastIn: UInt64 = 0
    private var lastOut: UInt64 = 0
    private var since = 0.0
    private var peak = 64_000.0
    private var rateIn = 0.0, rateOut = 0.0
    private let samples = 220

    init() {
        down = [Double](repeating: 0, count: samples)
        up = down
        let (i, o) = Self.counters()
        lastIn = i; lastOut = o
    }

    /// Sum of every non-loopback link-layer interface.
    private static func counters() -> (UInt64, UInt64) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let start = head else { return (0, 0) }
        defer { freeifaddrs(head) }
        var bytesIn: UInt64 = 0, bytesOut: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = start
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            guard let addr = cur.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK),
                  let raw = cur.pointee.ifa_data else { continue }
            let name = String(cString: cur.pointee.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            let d = raw.assumingMemoryBound(to: if_data.self).pointee
            bytesIn += UInt64(d.ifi_ibytes)
            bytesOut += UInt64(d.ifi_obytes)
        }
        return (bytesIn, bytesOut)
    }

    func update(dt: Double, size: CGSize) {
        since += dt
        guard since >= 0.35 else { return }
        let window = since
        since = 0
        let (i, o) = Self.counters()
        // counters are cumulative and can wrap or reset
        let dIn = i >= lastIn ? Double(i - lastIn) : 0
        let dOut = o >= lastOut ? Double(o - lastOut) : 0
        lastIn = i; lastOut = o
        rateIn = dIn / window
        rateOut = dOut / window
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
        let bits = bytesPerSecond
        if bits > 1_000_000 { return String(format: "%.1f MB/s", bits / 1_000_000) }
        if bits > 1_000 { return String(format: "%.0f KB/s", bits / 1_000) }
        return String(format: "%.0f B/s", bits)
    }
}
