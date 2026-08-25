import CoreGraphics
import Foundation
import ImageIO

/// Reads what Spotify is playing.
///
/// MediaRemote would be the nicer source, but Apple gated
/// `MRMediaRemoteGetNowPlayingInfo` behind an entitlement in macOS 15.4 and it
/// returns nil here, so this goes through Spotify's own AppleScript interface.
/// That needs Automation permission, which macOS asks for on first use.
final class NowPlaying {
    static let shared = NowPlaying()

    enum State: String { case playing, paused, stopped, unavailable }

    private(set) var state: State = .unavailable
    private(set) var track = ""
    private(set) var artist = ""
    private(set) var album = ""
    private(set) var duration = 0.0
    private(set) var position = 0.0
    private(set) var artwork: CGImage?
    private(set) var accent = CGColor(red: 0.11, green: 0.73, blue: 0.33, alpha: 1)
    private(set) var problem: String?

    private var artworkURL = ""
    private var polling = false
    private var sincePoll = 9.0
    private let queue = DispatchQueue(label: "com.touchbartoys.nowplaying")
    private let lock = NSLock()

    /// `is running` first, so this never launches Spotify just by asking.
    private let script = NSAppleScript(source: """
    if application "Spotify" is running then
        tell application "Spotify"
            return (player state as text) & "\\t" & (name of current track) ¬
                & "\\t" & (artist of current track) & "\\t" & (album of current track) ¬
                & "\\t" & (duration of current track) & "\\t" & (player position) ¬
                & "\\t" & (artwork url of current track)
        end tell
    else
        return "notrunning"
    end if
    """)

    /// Set TBT_FAKE_NOWPLAYING to render the scene with sample data, so the
    /// layout can be checked without a player running.
    private lazy var faking = ProcessInfo.processInfo.environment["TBT_FAKE_NOWPLAYING"] != nil

    /// Call once a frame. Polls about once a second and runs the clock forward
    /// in between, so the progress bar moves smoothly without a poll per frame.
    func tick(dt: Double) {
        if faking { fake(dt: dt); return }
        lock.lock()
        if state == .playing, duration > 0 {
            position = min(duration, position + dt)
        }
        sincePoll += dt
        let due = sincePoll >= 1.0 && !polling
        if due { sincePoll = 0; polling = true }
        lock.unlock()
        if due { queue.async { self.poll() } }
    }

    private func fake(dt: Double) {
        lock.lock()
        defer { lock.unlock() }
        if state != .playing {
            state = .playing
            track = "Everything In Its Right Place"
            artist = "Radiohead"
            album = "Kid A"
            duration = 251
            position = 96
            artwork = Self.placeholderArtwork()
            accent = CGColor(red: 0.94, green: 0.42, blue: 0.20, alpha: 1)
            problem = nil
        }
        position = min(duration, position + dt)
    }

    private static func placeholderArtwork() -> CGImage? {
        let side = 64
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { return nil }
        for y in 0..<side {
            let f = Double(y) / Double(side)
            ctx.setFillColor(CGColor(red: 0.95 - f * 0.5, green: 0.35 + f * 0.1,
                                     blue: 0.15 + f * 0.35, alpha: 1))
            ctx.fill(CGRect(x: 0, y: y, width: side, height: 1))
        }
        return ctx.makeImage()
    }

    private func poll() {
        defer { lock.lock(); polling = false; lock.unlock() }
        var error: NSDictionary?
        guard let result = script?.executeAndReturnError(&error).stringValue else {
            let message = (error?[NSAppleScript.errorMessage] as? String) ?? "Apple event failed"
            let number = (error?[NSAppleScript.errorNumber] as? Int) ?? 0
            lock.lock()
            state = .unavailable
            // -1743 is "not authorised to send Apple events"
            problem = number == -1743
                ? "Allow Touch Bar Toys to control Spotify in System Settings"
                : message
            lock.unlock()
            return
        }
        if result == "notrunning" {
            lock.lock(); state = .unavailable; problem = "Spotify isn't running"; lock.unlock()
            return
        }
        let f = result.components(separatedBy: "\t")
        guard f.count >= 7 else { return }
        // Spotify formats these in the user's locale, so the decimal separator
        // can be a comma. Double() only accepts a period.
        func number(_ s: String) -> Double {
            Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0
        }
        lock.lock()
        state = State(rawValue: f[0]) ?? .stopped
        track = f[1]; artist = f[2]; album = f[3]
        duration = number(f[4]) / 1000
        position = number(f[5])
        problem = nil
        let url = f[6]
        let needsArt = url != artworkURL && !url.isEmpty
        if needsArt { artworkURL = url }
        lock.unlock()
        if needsArt { fetchArtwork(url) }
    }

    private func fetchArtwork(_ urlString: String) {
        guard let url = URL(string: urlString), let data = try? Data(contentsOf: url),
              let src = CGImageSourceCreateWithData(data as CFData, nil) else { return }
        // decoded straight to bar height, so nothing large is kept around
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 96,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
        else { return }
        let color = Self.dominantColour(image)
        lock.lock()
        artwork = image
        accent = color
        lock.unlock()
    }

    /// Average the cover, then push saturation up so the accent reads as a
    /// colour rather than as mud.
    private static func dominantColour(_ image: CGImage) -> CGColor {
        let side = 12
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &pixels, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return CGColor(red: 0.11, green: 0.73, blue: 0.33, alpha: 1) }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var r = 0.0, g = 0.0, b = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            r += Double(pixels[i]); g += Double(pixels[i + 1]); b += Double(pixels[i + 2])
        }
        let n = Double(side * side) * 255
        r /= n; g /= n; b /= n
        let peak = max(r, max(g, b)), trough = min(r, min(g, b))
        let mid = (peak + trough) / 2
        let boost = 1.7
        func lift(_ c: Double) -> Double { min(1, max(0.12, mid + (c - mid) * boost)) }
        // and keep it bright enough to show on a black bar
        let lifted = (lift(r), lift(g), lift(b))
        let scale = max(0.55, max(lifted.0, max(lifted.1, lifted.2)))
        return CGColor(red: lifted.0 / scale, green: lifted.1 / scale,
                       blue: lifted.2 / scale, alpha: 1)
    }

    /// Snapshot, so drawing never reads a half-updated poll.
    func snapshot() -> (state: State, track: String, artist: String, duration: Double,
                        position: Double, artwork: CGImage?, accent: CGColor, problem: String?) {
        lock.lock()
        defer { lock.unlock() }
        return (state, track, artist, duration, position, artwork, accent, problem)
    }
}
