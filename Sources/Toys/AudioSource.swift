import AppKit
import AudioToolbox
import CoreAudio
import Foundation

/// Live system audio, plus which app it is coming from.
///
/// Uses the macOS 14.4 process-tap API, which reaches the output stream without
/// a loopback device and without Screen Recording. It does need audio-capture
/// permission: without it the tap still delivers buffers, they are just all
/// zeroes, which is what `permissionLikelyDenied` watches for.
final class AudioSource {
    static let shared = AudioSource()

    /// Downsampled recent audio, newest last, each entry 0...1.
    private(set) var envelope = [Float](repeating: 0, count: 220)
    private(set) var level: Float = 0

    private(set) var appName: String?
    private(set) var appIcon: CGImage?
    private(set) var isPlaying = false
    private(set) var running = false
    private(set) var permissionLikelyDenied = false

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    private var ring = [Float](repeating: 0, count: 220)
    private var writeIndex = 0
    private var chunkPeak: Float = 0
    private var chunkCount = 0
    private var samplesPerSlot = 380

    /// Seconds since the process scan last saw anything producing output.
    /// Deliberately independent of the audio level: when permission is denied
    /// the level is always zero, and that must not read as "nothing playing".
    private var sinceSeenPlaying = 99.0
    private var sinceScan = 9.0
    private var silentFor = 0.0
    private var scanning = false
    private var iconPID: pid_t = -1
    private var bundleIcons: [String: CGImage?] = [:]
    private let queue = DispatchQueue(label: "com.touchbartoys.audio")

    /// Apps we'd always believe over anything else claiming the output.
    private static let knownPlayers: Set<String> = [
        "com.spotify.client", "com.apple.Music", "com.apple.podcasts", "com.apple.TV",
        "com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox",
        "com.brave.Browser", "company.thebrowser.Browser", "com.microsoft.edgemac",
        "org.videolan.vlc", "com.colliderli.iina", "com.apple.QuickTimePlayerX",
        "tv.plex.desktop", "com.netflix.Netflix",
    ]

    // MARK: - Lifecycle

    func start() {
        // Only the app bundle taps audio. The offscreen renderer links this
        // too, and it has no business creating aggregate devices to draw a PNG.
        guard Bundle.main.bundleIdentifier != nil else { return }
        guard !running else { return }
        running = true
        guard createTap() else { running = false; return }
    }

    func stop() {
        guard running else { return }
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        aggregateID = kAudioObjectUnknown
        tapID = kAudioObjectUnknown
        running = false
    }

    private func createTap() -> Bool {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Touch Bar Toys"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { return false }

        var subDevices: [[String: Any]] = []
        if let uid = Self.defaultOutputUID() {
            subDevices = [[kAudioSubDeviceUIDKey as String: uid]]
        }
        let settings: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Touch Bar Toys Tap",
            kAudioAggregateDeviceUIDKey as String: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceSubDeviceListKey as String: subDevices,
            kAudioAggregateDeviceTapListKey as String: [
                [kAudioSubTapDriftCompensationKey as String: true,
                 kAudioSubTapUIDKey as String: description.uuid.uuidString],
            ],
        ]
        guard AudioHardwareCreateAggregateDevice(settings as CFDictionary,
                                                 &aggregateID) == noErr else { return false }

        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) {
            [weak self] _, inData, _, _, _ in
            self?.consume(inData)
        }
        guard status == noErr, let procID else { return false }
        return AudioDeviceStart(aggregateID, procID) == noErr
    }

    /// Runs on the audio thread, so no locks and no allocation. A torn read on
    /// the visualiser side is invisible.
    private func consume(_ list: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: list))
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let samples = data.assumingMemoryBound(to: Float.self)
            for i in 0..<count {
                let magnitude = abs(samples[i])
                if magnitude > chunkPeak { chunkPeak = magnitude }
                chunkCount += 1
                if chunkCount >= samplesPerSlot {
                    ring[writeIndex] = chunkPeak
                    writeIndex = (writeIndex + 1) % ring.count
                    chunkPeak = 0
                    chunkCount = 0
                }
            }
            break                       // one channel is plenty for a silhouette
        }
    }

    // MARK: - Per-frame

    func tick(dt: Double) {
        start()
        // unwrap the ring so the newest sample is last
        var out = [Float](repeating: 0, count: ring.count)
        let head = writeIndex
        for i in 0..<ring.count { out[i] = ring[(head + i) % ring.count] }
        envelope = out
        level = out.suffix(24).max() ?? 0

        sinceSeenPlaying += dt
        isPlaying = sinceSeenPlaying < 2.5

        sinceScan += dt
        if sinceScan >= 1.0, !scanning {
            sinceScan = 0
            scanning = true
            DispatchQueue.global(qos: .utility).async { self.scanProcesses() }
        }

        // Buffers arriving but always silent, while something is playing, means
        // the tap is running without permission.
        if isPlaying && level < 0.0001 {
            silentFor += dt
            if silentFor > 3 { permissionLikelyDenied = true }
        } else {
            silentFor = 0
            if level > 0.0001 { permissionLikelyDenied = false }
        }
    }

    // MARK: - Which app is making noise

    private func scanProcesses() {
        defer { scanning = false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr, size > 0
        else { return }
        var objects = [AudioObjectID](repeating: 0,
                                      count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                         0, nil, &size, &objects) == noErr else { return }

        let mine = ProcessInfo.processInfo.processIdentifier
        var best: (pid: pid_t, app: NSRunningApplication)?
        var bestRank = Int.max
        var anyPlaying = false
        for object in objects {
            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(object, &pidAddress, 0, nil,
                                             &pidSize, &pid) == noErr, pid != mine else { continue }
            var runAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningOutput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var isRunning: UInt32 = 0
            var runSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(object, &runAddress, 0, nil,
                                             &runSize, &isRunning) == noErr,
                  isRunning != 0 else { continue }
            // Menu-bar utilities can hold an output stream open without
            // playing anything (Pock does), so an accessory app claiming the
            // output is not evidence that audio is playing. Only foreground
            // apps, and known players, count.
            guard let app = NSRunningApplication(processIdentifier: pid),
                  let bundle = app.bundleIdentifier else { continue }
            let known = Self.knownPlayers.contains(bundle)
            guard known || app.activationPolicy == .regular else { continue }
            anyPlaying = true
            let rank = known ? 0 : 1
            if bestRank > rank { bestRank = rank; best = (pid, app) }
        }

        DispatchQueue.main.async {
            // hold for a moment, so a gap between tracks doesn't flicker it
            if anyPlaying { self.sinceSeenPlaying = 0 }
            guard let best else {
                if !anyPlaying { self.appName = nil; self.appIcon = nil; self.iconPID = -1 }
                return
            }
            self.appName = best.app.localizedName
            if self.iconPID != best.pid {
                self.iconPID = best.pid
                self.appIcon = Self.cgImage(best.app.icon)
            }
        }
    }

    /// Icon for a specific bundle, for when we know who is playing from a
    /// better source than the audio process list.
    func icon(forBundleID bundleID: String) -> CGImage? {
        if let cached = bundleIcons[bundleID] { return cached }
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        let image = Self.cgImage(app.icon)
        bundleIcons[bundleID] = image
        return image
    }

    private static func cgImage(_ image: NSImage?) -> CGImage? {
        guard let image else { return nil }
        var rect = CGRect(x: 0, y: 0, width: 64, height: 64)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func defaultOutputUID() -> String? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                         0, nil, &size, &device) == noErr else { return nil }
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(device, &uidAddress, 0, nil,
                                         &uidSize, &uid) == noErr else { return nil }
        return uid as String
    }
}
