import CoreGraphics
import Foundation

/// A wave packet of nested curves driven by whatever is playing, with the
/// source app's icon at the left.
///
/// The amplitude is real audio off the system tap. The oscillation it rides on
/// is drawn, because a peak envelope has no sign to it: this is a wave packet
/// shape modulated by the live level, not a sample-accurate trace.
final class AudioWaveToy: Toy {
    let title = "Audio Waveform"
    let emoji = "🎵"

    private let audio = AudioSource.shared
    private var t = 0.0
    private var smoothed = [Double](repeating: 0, count: 220)
    private var idle = 0.0
    /// True when the tap is delivering silence, which means audio-capture
    /// permission hasn't been granted. The packet is then driven by a
    /// synthetic envelope so the scene still works.
    private var synthetic = false
    private var sinceRealAudio = 99.0
    /// Forces the drawn envelope, for checking the look without a player.
    private let forceSynthetic =
        ProcessInfo.processInfo.environment["TBT_FORCE_SYNTH_WAVE"] != nil

    private let layers = 13

    func update(dt: Double, size: CGSize) {
        t += dt
        audio.tick(dt: dt)
        let live = audio.envelope
        for i in 0..<min(smoothed.count, live.count) {
            let target = Double(live[i])
            // rises fast, falls slowly, so the shape doesn't flicker
            let rate = target > smoothed[i] ? 16.0 : 5.0
            smoothed[i] += (target - smoothed[i]) * min(1, rate * dt)
        }
        // Real audio wins whenever there is any. If something is playing but
        // the tap is handing us silence, fall back to a drawn envelope rather
        // than showing a dead line.
        if audio.level > 0.0008 { sinceRealAudio = 0 } else { sinceRealAudio += dt }
        let haveRealAudio = sinceRealAudio < 4
        synthetic = forceSynthetic || (!haveRealAudio && audio.isPlaying)
        idle = (haveRealAudio || audio.isPlaying || forceSynthetic)
            ? 0 : min(1, idle + dt * 1.2)
    }

    func draw(in ctx: CGContext, size: CGSize) {
        ctx.setFillColor(CGColor(gray: 0.02, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))

        let iconSide = size.height - 8
        let iconRect = CGRect(x: 5, y: 4, width: iconSide, height: iconSide)
        if let icon = audio.appIcon {
            ctx.saveGState()
            ctx.setAlpha(audio.isPlaying ? 1 : 0.45)
            ctx.draw(icon, in: iconRect)
            ctx.restoreGState()
        } else {
            ctx.setStrokeColor(CGColor(gray: 0.28, alpha: 1))
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: iconRect.insetBy(dx: 3, dy: 3))
        }

        let area = CGRect(x: iconRect.maxX + 8, y: 0,
                          width: size.width - iconRect.maxX - 14, height: size.height)
        guard area.width > 60 else { return }
        packet(ctx, area)

        // Mention the permission briefly, then get out of the way. The scene
        // is still worth looking at on the synthetic envelope.
        if synthetic, t < 10 {
            Text.draw("SYNTHETIC - ALLOW SYSTEM AUDIO RECORDING FOR LIVE AUDIO", in: ctx,
                      at: CGPoint(x: area.maxX, y: 1.5),
                      size: 5.5, color: CGColor(gray: 0.26, alpha: 1), align: .right)
        }
    }

    private func packet(_ ctx: CGContext, _ area: CGRect) {
        let steps = max(60, min(260, Int(area.width / 3.4)))
        let mid = area.midY
        let maxAmp = area.height / 2 - 1

        // how loud things are right now, with a floor so it never fully dies
        let measured = max(0.06, Double(audio.level))
        let invented = 0.80 + 0.14 * sin(t * 0.83) + 0.06 * sin(t * 2.1 + 1.3)
        // damps all the way to zero, so an idle bar is a still flat line
        // rather than a line that keeps rippling with nothing playing
        let loudness = (synthetic ? invented : measured) * (1 - idle)

        var displacement = [CGFloat](repeating: 0, count: steps + 1)
        for i in 0...steps {
            let x = Double(i) / Double(steps)
            // envelope: the packet sits in the middle and flattens to a line
            let window = exp(-pow((x - 0.5) / 0.27, 2) / 2)
            // the live level shapes the packet along its length
            let localLevel: Double
            if synthetic {
                localLevel = 0.72 + 0.18 * abs(sin(t * 1.6 + x * 6.2))
                           + 0.10 * abs(sin(t * 3.1 + x * 13.7))
            } else {
                localLevel = 0.55 + 0.45 * smoothed[Int(x * Double(smoothed.count - 1))]
            }
            // the oscillation the packet rides on, normalised so the three
            // components reach the full swing rather than averaging each other
            // away: unnormalised this bottomed out around two points of travel
            let raw = sin(x * 15.0 - t * 3.1) * 0.55
                    + sin(x * 9.1 + t * 1.9) * 0.32
                    + sin(x * 29.0 - t * 4.7) * 0.16
            // soft saturation: a hard clamp gave the peaks flat tops
            let carrier = tanh(raw * 2.1)
            let amplitude = maxAmp * CGFloat(min(1.0, loudness * 2.2))
            displacement[i] = CGFloat(carrier * window * localLevel) * amplitude
        }

        // the flat line the packet emerges from
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.5))
        ctx.setLineWidth(0.9)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: area.minX, y: mid))
        ctx.addLine(to: CGPoint(x: area.maxX, y: mid))
        ctx.strokePath()

        // nested curves, each a fraction of the full swing
        for layer in 0..<layers {
            // weighted outward, so the curves fan across the full swing instead
            // of bunching against the baseline
            let fraction = Double(layer + 1) / Double(layers)
            let scale = CGFloat(pow(fraction, 0.55))
            let alpha = 0.09 + 0.26 * fraction
            ctx.beginPath()
            for i in 0...steps {
                let px = area.minX + area.width * CGFloat(i) / CGFloat(steps)
                let py = mid + displacement[i] * scale
                if i == 0 { ctx.move(to: CGPoint(x: px, y: py)) }
                else { ctx.addLine(to: CGPoint(x: px, y: py)) }
            }
            ctx.setLineWidth(0.7)
            ctx.setStrokeColor(CGColor(gray: 1, alpha: alpha))
            ctx.strokePath()
        }

        // a brighter core pass over the outermost curve, plus a soft halo
        for (width, alpha) in [(3.2, 0.055), (1.6, 0.13), (0.9, 0.55)] {
            ctx.beginPath()
            for i in 0...steps {
                let px = area.minX + area.width * CGFloat(i) / CGFloat(steps)
                let py = mid + displacement[i]
                if i == 0 { ctx.move(to: CGPoint(x: px, y: py)) }
                else { ctx.addLine(to: CGPoint(x: px, y: py)) }
            }
            ctx.setLineWidth(CGFloat(width))
            ctx.setStrokeColor(CGColor(gray: 1, alpha: alpha))
            ctx.strokePath()
        }
    }
}
