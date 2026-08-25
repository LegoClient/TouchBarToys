import CoreGraphics
import Darwin
import Foundation
import IOKit.ps

/// One place that samples everything the System scenes show, each at its own
/// sensible cadence. Shared, so several scenes reading the same counters don't
/// each keep their own deltas.
final class SystemStats {
    static let shared = SystemStats()

    // CPU
    private(set) var coreLoads: [Double] = []
    private(set) var cpuTotal = 0.0
    // memory, in bytes
    private(set) var wired = 0.0, active = 0.0, compressed = 0.0
    private(set) var totalRAM = Double(ProcessInfo.processInfo.physicalMemory)
    // disk, in bytes
    private(set) var diskUsed = 0.0, diskTotal = 0.0
    // network, in bytes per second
    private(set) var netIn = 0.0, netOut = 0.0
    // battery
    private(set) var batteryLevel = 0.0
    private(set) var charging = false, plugged = false
    private(set) var batteryMinutes = -1

    private var previousCPU: [(busy: Double, total: Double)] = []
    private var lastNetIn: UInt64 = 0, lastNetOut: UInt64 = 0
    private var sinceCPU = 9.0, sinceMemory = 9.0, sinceDisk = 99.0
    private var sinceNet = 9.0, sinceBattery = 99.0
    private var netWindow = 0.0

    private init() {
        let (i, o) = Self.interfaceCounters()
        lastNetIn = i; lastNetOut = o
    }

    /// Call once per frame. Each source refreshes on its own schedule.
    func tick(dt: Double) {
        sinceCPU += dt; sinceMemory += dt; sinceDisk += dt
        sinceNet += dt; sinceBattery += dt; netWindow += dt
        if sinceCPU >= 0.35 { sinceCPU = 0; sampleCPU() }
        if sinceNet >= 0.35 { sinceNet = 0; sampleNetwork() }
        if sinceMemory >= 2 { sinceMemory = 0; sampleMemory() }
        if sinceDisk >= 15 { sinceDisk = 0; sampleDisk() }
        if sinceBattery >= 5 { sinceBattery = 0; sampleBattery() }
    }

    // MARK: - CPU

    private func sampleCPU() {
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
        var snapshot: [(busy: Double, total: Double)] = []
        for i in 0..<n {
            let base = i * Int(CPU_STATE_MAX)
            let busy = Double(info[base + Int(CPU_STATE_USER)])
                     + Double(info[base + Int(CPU_STATE_SYSTEM)])
                     + Double(info[base + Int(CPU_STATE_NICE)])
            let total = busy + Double(info[base + Int(CPU_STATE_IDLE)])
            snapshot.append((busy: busy, total: total))
            if previousCPU.count == n {
                let db = busy - previousCPU[i].busy
                let dt = total - previousCPU[i].total
                loads[i] = dt > 0 ? max(0, min(1, db / dt)) : 0
            }
        }
        previousCPU = snapshot
        if !loads.isEmpty { coreLoads = loads }
        cpuTotal = coreLoads.isEmpty ? 0 : coreLoads.reduce(0, +) / Double(coreLoads.count)
    }

    // MARK: - Memory and disk

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
        totalRAM = Double(ProcessInfo.processInfo.physicalMemory)
    }

    private func sampleDisk() {
        let url = URL(fileURLWithPath: "/")
        guard let v = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
        ]) else { return }
        diskTotal = Double(v.volumeTotalCapacity ?? 0)
        diskUsed = max(0, diskTotal - Double(v.volumeAvailableCapacityForImportantUsage ?? 0))
    }

    // MARK: - Network

    /// Sum of every non-loopback link-layer interface.
    static func interfaceCounters() -> (UInt64, UInt64) {
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
            guard !String(cString: cur.pointee.ifa_name).hasPrefix("lo") else { continue }
            let d = raw.assumingMemoryBound(to: if_data.self).pointee
            bytesIn += UInt64(d.ifi_ibytes)
            bytesOut += UInt64(d.ifi_obytes)
        }
        return (bytesIn, bytesOut)
    }

    private func sampleNetwork() {
        let (i, o) = Self.interfaceCounters()
        let window = max(0.05, netWindow)
        netWindow = 0
        // counters are cumulative and can reset
        netIn = i >= lastNetIn ? Double(i - lastNetIn) / window : 0
        netOut = o >= lastNetOut ? Double(o - lastNetOut) / window : 0
        lastNetIn = i; lastNetOut = o
    }

    // MARK: - Battery

    private func sampleBattery() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            let cur = (d[kIOPSCurrentCapacityKey as String] as? Int) ?? 0
            let max = (d[kIOPSMaxCapacityKey as String] as? Int) ?? 100
            batteryLevel = max > 0 ? Double(cur) / Double(max) : 0
            charging = (d[kIOPSIsChargingKey as String] as? Bool) ?? false
            plugged = (d[kIOPSPowerSourceStateKey as String] as? String)
                == (kIOPSACPowerValue as String)
            batteryMinutes = charging
                ? (d[kIOPSTimeToFullChargeKey as String] as? Int) ?? -1
                : (d[kIOPSTimeToEmptyKey as String] as? Int) ?? -1
            return
        }
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond > 1_000_000 { return String(format: "%.1fM", bytesPerSecond / 1_000_000) }
        if bytesPerSecond > 1_000 { return String(format: "%.0fK", bytesPerSecond / 1_000) }
        return String(format: "%.0fB", bytesPerSecond)
    }
}
