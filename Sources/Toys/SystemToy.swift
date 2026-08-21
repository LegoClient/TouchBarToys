import CoreGraphics
import Darwin
import Foundation

/// Memory pressure and disk usage, to round out the system-monitor set.
final class SystemToy: Toy {
    let title = "Memory & Disk"
    let emoji = "💾"

    private var wired = 0.0, active = 0.0, compressed = 0.0, free = 0.0
    private var totalRAM = 0.0
    private var diskUsed = 0.0, diskTotal = 0.0
    private var since = 9.0

    func update(dt: Double, size: CGSize) {
        since += dt
        guard since >= 2 else { return }
        since = 0
        sampleMemory()
        sampleDisk()
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride /
                                           MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let page = Double(vm_kernel_page_size)
        wired = Double(stats.wire_count) * page
        active = Double(stats.active_count) * page
        compressed = Double(stats.compressor_page_count) * page
        free = (Double(stats.free_count) + Double(stats.inactive_count)) * page
        totalRAM = Double(ProcessInfo.processInfo.physicalMemory)
    }

    private func sampleDisk() {
        let url = URL(fileURLWithPath: "/")
        guard let v = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
        ]) else { return }
        let total = Double(v.volumeTotalCapacity ?? 0)
        let avail = Double(v.volumeAvailableCapacityForImportantUsage ?? 0)
        diskTotal = total
        diskUsed = max(0, total - avail)
    }

    func draw(in ctx: CGContext, size: CGSize) {
        ctx.setFillColor(CGColor(gray: 0.03, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))

        let rowH = (size.height - 7) / 2
        let x0: CGFloat = 46
        let w = size.width - x0 - 8

        // memory, split by kind
        guard totalRAM > 0 else { return }
        let segments: [(Double, CGColor)] = [
            (wired, CGColor(red: 1.0, green: 0.42, blue: 0.38, alpha: 1)),
            (active, CGColor(red: 0.42, green: 0.78, blue: 1.0, alpha: 1)),
            (compressed, CGColor(red: 1.0, green: 0.75, blue: 0.30, alpha: 1)),
        ]
        let yMem = size.height - 3 - rowH
        ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
        ctx.fill(CGRect(x: x0, y: yMem, width: w, height: rowH - 2))
        var x = x0
        for (bytes, color) in segments {
            let segW = w * CGFloat(bytes / totalRAM)
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: x, y: yMem, width: segW, height: rowH - 2))
            x += segW
        }
        Text.draw("RAM", in: ctx, at: CGPoint(x: 8, y: yMem + 1), size: 8,
                  color: CGColor(gray: 0.5, alpha: 1))
        let usedGB = (wired + active + compressed) / 1_073_741_824
        let totalGB = totalRAM / 1_073_741_824
        Text.draw(String(format: "%.1f / %.0f GB", usedGB, totalGB),
                  in: ctx, at: CGPoint(x: size.width - 10, y: yMem + 1), size: 8,
                  color: CGColor(gray: 0.75, alpha: 1), align: .right)

        // disk
        let yDisk = yMem - rowH - 1
        ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
        ctx.fill(CGRect(x: x0, y: yDisk, width: w, height: rowH - 2))
        if diskTotal > 0 {
            let frac = CGFloat(diskUsed / diskTotal)
            ctx.setFillColor(frac > 0.9
                             ? CGColor(red: 1.0, green: 0.35, blue: 0.3, alpha: 1)
                             : CGColor(red: 0.55, green: 0.85, blue: 0.55, alpha: 1))
            ctx.fill(CGRect(x: x0, y: yDisk, width: w * frac, height: rowH - 2))
            let freeGB = (diskTotal - diskUsed) / 1_000_000_000
            Text.draw(String(format: "%.0f GB FREE", freeGB),
                      in: ctx, at: CGPoint(x: size.width - 10, y: yDisk + 1), size: 8,
                      color: CGColor(gray: 0.75, alpha: 1), align: .right)
        }
        Text.draw("DISK", in: ctx, at: CGPoint(x: 8, y: yDisk + 1), size: 8,
                  color: CGColor(gray: 0.5, alpha: 1))
    }
}
