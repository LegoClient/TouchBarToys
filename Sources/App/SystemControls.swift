import CoreAudio
import CoreGraphics
import Foundation

/// Screen brightness and output volume.
///
/// Brightness goes through DisplayServices, which is private, so its functions
/// are resolved with dlsym the same way DFRFoundation's are. Volume is plain
/// CoreAudio on the default output device.
enum SystemControls {

    // MARK: - Brightness

    private static let displayServices: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)

    private typealias GetBrightnessFn =
        @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFn =
        @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let getBrightnessFn: GetBrightnessFn? = {
        guard let h = displayServices, let s = dlsym(h, "DisplayServicesGetBrightness")
        else { return nil }
        return unsafeBitCast(s, to: GetBrightnessFn.self)
    }()

    private static let setBrightnessFn: SetBrightnessFn? = {
        guard let h = displayServices, let s = dlsym(h, "DisplayServicesSetBrightness")
        else { return nil }
        return unsafeBitCast(s, to: SetBrightnessFn.self)
    }()

    static var brightnessAvailable: Bool { getBrightnessFn != nil && setBrightnessFn != nil }

    /// Never goes fully dark. With the bar taken over by a scene the Control
    /// Strip's brightness keys aren't reachable, so a slider that bottoms out
    /// at zero would leave no visible way back.
    static let minimumBrightness = 0.05

    static var brightness: Double {
        get {
            guard let get = getBrightnessFn else { return 0 }
            var value: Float = 0
            return get(CGMainDisplayID(), &value) == 0 ? Double(value) : 0
        }
        set {
            guard let set = setBrightnessFn else { return }
            let clamped = min(1.0, max(minimumBrightness, newValue))
            _ = set(CGMainDisplayID(), Float(clamped))
        }
    }

    // MARK: - Volume

    private static var outputDevice: AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    private static func volumeAddress(_ selector: AudioObjectPropertySelector)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static var volumeAvailable: Bool {
        guard let device = outputDevice else { return false }
        var address = volumeAddress(kAudioDevicePropertyVolumeScalar)
        return AudioObjectHasProperty(device, &address)
    }

    static var volume: Double {
        get {
            guard let device = outputDevice else { return 0 }
            var address = volumeAddress(kAudioDevicePropertyVolumeScalar)
            guard AudioObjectHasProperty(device, &address) else { return 0 }
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
            return status == noErr ? Double(value) : 0
        }
        set {
            guard let device = outputDevice else { return }
            var address = volumeAddress(kAudioDevicePropertyVolumeScalar)
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(device, &address),
                  AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                  settable.boolValue else { return }
            var value = Float32(min(1.0, max(0.0, newValue)))
            _ = AudioObjectSetPropertyData(device, &address, 0, nil,
                                           UInt32(MemoryLayout<Float32>.size), &value)
            // Dragging the slider up off zero should also take it off mute.
            if newValue > 0.001 && muted { muted = false }
        }
    }

    static var muted: Bool {
        get {
            guard let device = outputDevice else { return false }
            var address = volumeAddress(kAudioDevicePropertyMute)
            guard AudioObjectHasProperty(device, &address) else { return false }
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
            return status == noErr && value != 0
        }
        set {
            guard let device = outputDevice else { return }
            var address = volumeAddress(kAudioDevicePropertyMute)
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(device, &address),
                  AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                  settable.boolValue else { return }
            var value: UInt32 = newValue ? 1 : 0
            _ = AudioObjectSetPropertyData(device, &address, 0, nil,
                                           UInt32(MemoryLayout<UInt32>.size), &value)
        }
    }
}
