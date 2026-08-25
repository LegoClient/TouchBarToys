import CoreGraphics
import Foundation

/// What Spotify is playing: cover, track, artist, and how much is left.
final class SpotifyToy: Toy {
    let title = "Spotify"
    let emoji = "🎧"

    private let now = NowPlaying.shared
    private var t = 0.0
    private var levels: [Double] = [0.4, 0.7, 0.55]
    private var scroll = 0.0

    func update(dt: Double, size: CGSize) {
        t += dt
        now.tick(dt: dt)
        // the little equaliser only moves while something is playing
        if now.snapshot().state == .playing {
            for i in levels.indices {
                let speed = 2.4 + Double(i) * 0.9
                levels[i] = 0.35 + 0.6 * abs(sin(t * speed + Double(i) * 1.7))
            }
            scroll += dt
        }
    }

    func draw(in ctx: CGContext, size: CGSize) {
        ctx.setFillColor(CGColor(gray: 0.03, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        let s = now.snapshot()

        guard s.state != .unavailable, !s.track.isEmpty else {
            let message = s.problem ?? "Nothing playing"
            Text.draw(message.uppercased(), in: ctx,
                      at: CGPoint(x: size.width / 2, y: size.height / 2 - 4),
                      size: 9, color: CGColor(gray: 0.5, alpha: 1), align: .center)
            return
        }

        // the cover's colour bleeding to the right, which is the whole look
        wash(ctx, size, s.accent)

        let art = CGRect(x: 4, y: 2, width: size.height - 4, height: size.height - 4)
        cover(ctx, art, s.artwork, paused: s.state != .playing)

        let eqX = art.maxX + 7
        equaliser(ctx, x: eqX, midY: size.height / 2, playing: s.state == .playing,
                  color: s.accent)

        let infoX = eqX + 15
        let infoW = min(300, max(110, (size.width - infoX) * 0.34))
        let clipped = CGRect(x: infoX, y: 0, width: infoW, height: size.height)
        Text.draw(fit(s.track, size: 11, width: clipped.width), in: ctx,
                  at: CGPoint(x: infoX, y: size.height / 2 + 1),
                  size: 11, color: CGColor(gray: 0.96, alpha: 1))
        Text.draw(fit(s.artist, size: 8.5, width: clipped.width), in: ctx,
                  at: CGPoint(x: infoX, y: 6),
                  size: 8.5, color: CGColor(gray: 0.56, alpha: 1))

        progress(ctx, from: infoX + infoW + 16, to: size.width - 12,
                 midY: size.height / 2, snapshot: s)
    }

    // MARK: - Pieces

    private func wash(_ ctx: CGContext, _ size: CGSize, _ accent: CGColor) {
        guard let comps = accent.components, comps.count >= 3 else { return }
        let colors = [
            CGColor(red: comps[0], green: comps[1], blue: comps[2], alpha: 0.26),
            CGColor(red: comps[0], green: comps[1], blue: comps[2], alpha: 0),
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: min(size.width, 380), height: size.height))
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0),
                               end: CGPoint(x: min(size.width, 380), y: 0), options: [])
        ctx.restoreGState()
    }

    private func cover(_ ctx: CGContext, _ r: CGRect, _ image: CGImage?, paused: Bool) {
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 4, cornerHeight: 4, transform: nil))
        ctx.clip()
        if let image {
            ctx.draw(image, in: r)
        } else {
            ctx.setFillColor(CGColor(gray: 0.16, alpha: 1))
            ctx.fill(r)
        }
        if paused {
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.55))
            ctx.fill(r)
        }
        ctx.restoreGState()
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.16))
        ctx.setLineWidth(1)
        ctx.addPath(CGPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5),
                           cornerWidth: 4, cornerHeight: 4, transform: nil))
        ctx.strokePath()

        if paused {
            ctx.setFillColor(CGColor(gray: 0.95, alpha: 0.9))
            let c = CGPoint(x: r.midX, y: r.midY)
            ctx.fill(CGRect(x: c.x - 4, y: c.y - 5, width: 2.8, height: 10))
            ctx.fill(CGRect(x: c.x + 1.2, y: c.y - 5, width: 2.8, height: 10))
        }
    }

    private func equaliser(_ ctx: CGContext, x: CGFloat, midY: CGFloat,
                           playing: Bool, color: CGColor) {
        for i in 0..<3 {
            let level = playing ? levels[i] : 0.22
            let h = CGFloat(level) * 15
            let bx = x + CGFloat(i) * 4
            ctx.setFillColor(playing ? color : CGColor(gray: 0.35, alpha: 1))
            ctx.addPath(CGPath(roundedRect: CGRect(x: bx, y: midY - h / 2, width: 2.6, height: h),
                               cornerWidth: 1.3, cornerHeight: 1.3, transform: nil))
            ctx.fillPath()
        }
    }

    private func progress(_ ctx: CGContext, from x0: CGFloat, to x1: CGFloat, midY: CGFloat,
                          snapshot s: (state: NowPlaying.State, track: String, artist: String,
                                       duration: Double, position: Double, artwork: CGImage?,
                                       accent: CGColor, problem: String?)) {
        guard x1 - x0 > 90 else { return }
        let elapsed = Self.clock(s.position)
        let left = Self.clock(max(0, s.duration - s.position))
        Text.draw(elapsed, in: ctx, at: CGPoint(x: x0, y: midY - 3.5),
                  size: 8.5, color: CGColor(gray: 0.72, alpha: 1))
        Text.draw("-" + left, in: ctx, at: CGPoint(x: x1, y: midY - 3.5),
                  size: 8.5, color: CGColor(gray: 0.72, alpha: 1), align: .right)

        let barX = x0 + 32
        let barW = (x1 - 34) - barX
        guard barW > 20 else { return }
        let track = CGRect(x: barX, y: midY - 2.5, width: barW, height: 5)
        ctx.setFillColor(CGColor(gray: 0.19, alpha: 1))
        ctx.addPath(CGPath(roundedRect: track, cornerWidth: 2.5, cornerHeight: 2.5,
                           transform: nil))
        ctx.fillPath()

        let frac = s.duration > 0 ? CGFloat(min(1, s.position / s.duration)) : 0
        let filled = CGRect(x: track.minX, y: track.minY, width: max(5, track.width * frac),
                            height: track.height)
        // a soft halo under the played portion, same trick as the dashboard
        if let halo = s.accent.copy(alpha: 0.30) {
            ctx.setFillColor(halo)
            let glow = filled.insetBy(dx: -2.5, dy: -2.5)
            ctx.addPath(CGPath(roundedRect: glow, cornerWidth: 5, cornerHeight: 5,
                               transform: nil))
            ctx.fillPath()
        }
        ctx.setFillColor(s.accent)
        ctx.addPath(CGPath(roundedRect: filled, cornerWidth: 2.5, cornerHeight: 2.5,
                           transform: nil))
        ctx.fillPath()

        // playhead
        ctx.setFillColor(CGColor(gray: 0.98, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: filled.maxX - 4, y: midY - 4, width: 8, height: 8))
    }

    // MARK: - Helpers

    private static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Trim with an ellipsis until it fits the column.
    private func fit(_ s: String, size: CGFloat, width: CGFloat) -> String {
        guard Text.width(s, size: size) > width else { return s }
        var out = s
        while !out.isEmpty, Text.width(out + "…", size: size) > width {
            out.removeLast()
        }
        return out + "…"
    }
}
