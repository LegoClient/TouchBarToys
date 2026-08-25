import CoreGraphics
import Foundation

/// Brightness and volume sliders, drawn by hand like everything else on the
/// bar. Double-tapping the scene shows it, double-tapping again hides it.
final class ControlPanel {

    private enum Drag { case none, brightness, volume }

    private var brightness = 0.0
    private var volume = 0.0
    private var muted = false
    private var drag: Drag = .none
    private var sinceRefresh = 9.0
    private var flashMute = 0.0

    /// Pull the live values in. Skipped mid-drag so the slider doesn't fight
    /// the finger while the system catches up.
    func refresh() {
        guard drag == .none else { return }
        brightness = SystemControls.brightness
        volume = SystemControls.volume
        muted = SystemControls.muted
    }

    func update(dt: Double) {
        flashMute = max(0, flashMute - dt)
        sinceRefresh += dt
        if sinceRefresh >= 0.4 {
            sinceRefresh = 0
            refresh()
        }
    }

    // MARK: - Layout

    private struct Layout {
        var brightIcon: CGRect, brightTrack: CGRect, brightLabel: CGPoint
        var volIcon: CGRect, volTrack: CGRect, volLabel: CGPoint
        var close: CGRect
        var midX: CGFloat
    }

    private func layout(_ size: CGSize) -> Layout {
        let h = size.height
        let closeW: CGFloat = 18
        let close = CGRect(x: size.width - closeW - 12, y: (h - closeW) / 2,
                           width: closeW, height: closeW)
        let available = close.minX - 12 - 12
        let gap: CGFloat = 20
        let groupW = (available - gap) / 2
        let trackH: CGFloat = 8
        let labelW: CGFloat = 42

        func group(_ x: CGFloat) -> (CGRect, CGRect, CGPoint) {
            let icon = CGRect(x: x, y: (h - 18) / 2, width: 18, height: 18)
            let trackX = x + 26
            let trackW = groupW - 26 - labelW
            let track = CGRect(x: trackX, y: (h - trackH) / 2, width: trackW, height: trackH)
            let label = CGPoint(x: x + groupW, y: h / 2 - 4)
            return (icon, track, label)
        }

        let (bi, bt, bl) = group(12)
        let (vi, vt, vl) = group(12 + groupW + gap)
        return Layout(brightIcon: bi, brightTrack: bt, brightLabel: bl,
                      volIcon: vi, volTrack: vt, volLabel: vl,
                      close: close, midX: 12 + groupW + gap / 2)
    }

    // MARK: - Input

    /// Returns true when the panel wants to be dismissed.
    func began(at p: CGPoint, size: CGSize) -> Bool {
        let l = layout(size)
        if l.close.insetBy(dx: -10, dy: -10).contains(p) { return true }
        if l.volIcon.insetBy(dx: -6, dy: -10).contains(p) {
            muted.toggle()
            SystemControls.muted = muted
            flashMute = 0.25
            return false
        }
        // Generous vertical hit area: the bar is only 30pt tall.
        if p.x < l.midX {
            drag = .brightness
            setBrightness(from: p, l)
        } else {
            drag = .volume
            setVolume(from: p, l)
        }
        return false
    }

    func moved(at p: CGPoint, size: CGSize) {
        let l = layout(size)
        switch drag {
        case .brightness: setBrightness(from: p, l)
        case .volume: setVolume(from: p, l)
        case .none: break
        }
    }

    func ended() { drag = .none }

    private func fraction(_ p: CGPoint, _ track: CGRect) -> Double {
        Double(min(1, max(0, (p.x - track.minX) / track.width)))
    }

    private func setBrightness(from p: CGPoint, _ l: Layout) {
        brightness = max(SystemControls.minimumBrightness, fraction(p, l.brightTrack))
        SystemControls.brightness = brightness
    }

    private func setVolume(from p: CGPoint, _ l: Layout) {
        volume = fraction(p, l.volTrack)
        SystemControls.volume = volume
        if volume > 0.001 { muted = false }
    }

    // MARK: - Drawing

    func draw(in ctx: CGContext, size: CGSize) {
        let l = layout(size)
        let warm = CGColor(red: 1.0, green: 0.82, blue: 0.38, alpha: 1)
        let cool = CGColor(red: 0.36, green: 0.70, blue: 1.0, alpha: 1)
        let dim = CGColor(gray: 0.62, alpha: 1)

        sun(ctx, in: l.brightIcon, color: warm)
        slider(ctx, track: l.brightTrack, value: brightness, color: warm)
        Text.draw("\(Int((brightness * 100).rounded()))%", in: ctx, at: l.brightLabel,
                  size: 11, color: dim, align: .right)

        let volColor = muted ? CGColor(gray: 0.45, alpha: 1) : cool
        speaker(ctx, in: l.volIcon, color: flashMute > 0 ? CGColor(gray: 1, alpha: 1) : volColor,
                muted: muted)
        slider(ctx, track: l.volTrack, value: muted ? 0 : volume, color: volColor)
        Text.draw(muted ? "MUTE" : "\(Int((volume * 100).rounded()))%",
                  in: ctx, at: l.volLabel, size: 11, color: dim, align: .right)

        closeGlyph(ctx, in: l.close)
    }

    private func slider(_ ctx: CGContext, track: CGRect, value: Double, color: CGColor) {
        let radius = track.height / 2
        ctx.setFillColor(CGColor(gray: 0.26, alpha: 1))
        ctx.addPath(CGPath(roundedRect: track, cornerWidth: radius, cornerHeight: radius,
                           transform: nil))
        ctx.fillPath()

        let w = max(track.height, track.width * CGFloat(min(1, max(0, value))))
        let filled = CGRect(x: track.minX, y: track.minY, width: w, height: track.height)
        ctx.setFillColor(color)
        ctx.addPath(CGPath(roundedRect: filled, cornerWidth: radius, cornerHeight: radius,
                           transform: nil))
        ctx.fillPath()

        // knob
        let kx = track.minX + track.width * CGFloat(min(1, max(0, value)))
        let kr: CGFloat = 6.5
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: kx - kr - 1, y: track.midY - kr - 1,
                                   width: (kr + 1) * 2, height: (kr + 1) * 2))
        ctx.setFillColor(CGColor(gray: 0.97, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: kx - kr, y: track.midY - kr, width: kr * 2, height: kr * 2))
    }

    private func sun(_ ctx: CGContext, in r: CGRect, color: CGColor) {
        let c = CGPoint(x: r.midX, y: r.midY)
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: c.x - 3.4, y: c.y - 3.4, width: 6.8, height: 6.8))
        ctx.setStrokeColor(color)
        ctx.setLineWidth(1.4)
        ctx.setLineCap(.round)
        for i in 0..<8 {
            let a = Double(i) / 8 * 2 * .pi
            let inner: CGFloat = 5.4, outer: CGFloat = 8.2
            ctx.move(to: CGPoint(x: c.x + CGFloat(cos(a)) * inner, y: c.y + CGFloat(sin(a)) * inner))
            ctx.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * outer, y: c.y + CGFloat(sin(a)) * outer))
        }
        ctx.strokePath()
    }

    private func speaker(_ ctx: CGContext, in r: CGRect, color: CGColor, muted: Bool) {
        let c = CGPoint(x: r.midX - 2, y: r.midY)
        ctx.setFillColor(color)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: c.x - 6, y: c.y - 2.6))
        ctx.addLine(to: CGPoint(x: c.x - 2.6, y: c.y - 2.6))
        ctx.addLine(to: CGPoint(x: c.x + 1.6, y: c.y - 6.5))
        ctx.addLine(to: CGPoint(x: c.x + 1.6, y: c.y + 6.5))
        ctx.addLine(to: CGPoint(x: c.x - 2.6, y: c.y + 2.6))
        ctx.addLine(to: CGPoint(x: c.x - 6, y: c.y + 2.6))
        ctx.closePath()
        ctx.fillPath()

        ctx.setStrokeColor(color)
        ctx.setLineWidth(1.3)
        ctx.setLineCap(.round)
        if muted {
            ctx.move(to: CGPoint(x: c.x + 4, y: c.y - 3.4))
            ctx.addLine(to: CGPoint(x: c.x + 9, y: c.y + 3.4))
            ctx.move(to: CGPoint(x: c.x + 9, y: c.y - 3.4))
            ctx.addLine(to: CGPoint(x: c.x + 4, y: c.y + 3.4))
        } else {
            for (i, radius) in [CGFloat(4.0), 7.0].enumerated() {
                ctx.addArc(center: CGPoint(x: c.x + 1.6, y: c.y), radius: radius,
                           startAngle: -0.7, endAngle: 0.7, clockwise: false)
                ctx.setLineWidth(i == 0 ? 1.4 : 1.2)
                ctx.strokePath()
            }
        }
        ctx.strokePath()
    }

    private func closeGlyph(_ ctx: CGContext, in r: CGRect) {
        ctx.setFillColor(CGColor(gray: 0.18, alpha: 1))
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.fillPath()
        ctx.setStrokeColor(CGColor(gray: 0.85, alpha: 1))
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        let i: CGFloat = 5.5
        ctx.move(to: CGPoint(x: r.minX + i, y: r.minY + i))
        ctx.addLine(to: CGPoint(x: r.maxX - i, y: r.maxY - i))
        ctx.move(to: CGPoint(x: r.minX + i, y: r.maxY - i))
        ctx.addLine(to: CGPoint(x: r.maxX - i, y: r.minY + i))
        ctx.strokePath()
    }
}
