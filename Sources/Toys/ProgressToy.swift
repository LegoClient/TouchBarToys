import CoreGraphics
import Foundation

/// A progress bar that will never, ever finish.
final class ProgressToy: Toy {
    let title = "Almost Done"
    let emoji = "🐌"

    private let stages = [
        "RETICULATING SPLINES", "REVERSING ENTROPY", "WARMING UP THE TUBES",
        "COUNTING BACKWARDS FROM INFINITY", "ASKING NICELY", "CONSULTING THE MANUAL",
        "REBUILDING INDEX", "ALIGNING FLUX CAPACITORS", "TALKING TO THE SERVER",
        "WAITING FOR MUTEX", "DEFRAGMENTING VIBES", "ALMOST THERE",
    ]
    private var stage = 0
    private var progress = 0.0
    private var stageTime = 0.0
    private var t = 0.0
    private var eta = 41.0
    private var rng = RNG(seed: 0x9944)

    func tap(at p: CGPoint, size: CGSize) {
        // "helpfully" knock it back a bit
        progress = max(0.02, progress - rng.range(0.06, 0.2))
        stage = rng.int(stages.count)
    }

    func update(dt: Double, size: CGSize) {
        t += dt
        stageTime += dt
        // asymptotic crawl, with the occasional humiliating setback
        let remaining = max(0.0, 0.994 - progress)
        progress += remaining * 0.16 * dt
        if rng.d() < dt * 0.09 {
            progress = max(0.03, progress - rng.range(0.03, 0.14))
            stage = rng.int(stages.count)
            stageTime = 0
        }
        if stageTime > 4.5 {
            stageTime = 0
            stage = (stage + 1 + rng.int(3)) % stages.count
        }
        eta = max(3, eta + (rng.d() < 0.5 ? -1 : 1.6) * dt * 8)
    }

    func draw(in ctx: CGContext, size: CGSize) {
        ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))

        let barY = size.height * 0.22
        let barH = size.height * 0.42
        let track = CGRect(x: 10, y: barY, width: size.width - 20, height: barH)
        ctx.setFillColor(CGColor(gray: 0.14, alpha: 1))
        ctx.addPath(CGPath(roundedRect: track, cornerWidth: barH / 2, cornerHeight: barH / 2,
                           transform: nil))
        ctx.fillPath()

        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: track, cornerWidth: barH / 2, cornerHeight: barH / 2,
                           transform: nil))
        ctx.clip()
        let fillW = max(barH, track.width * CGFloat(progress))
        ctx.setFillColor(CGColor(red: 0.26, green: 0.58, blue: 0.98, alpha: 1))
        ctx.fill(CGRect(x: track.minX, y: track.minY, width: fillW, height: barH))
        // barber-pole stripes
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.14))
        var x = -barH * 2 + CGFloat((t * 26).truncatingRemainder(dividingBy: Double(barH * 2)))
        while x < track.minX + fillW {
            ctx.saveGState()
            ctx.translateBy(x: x, y: 0)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 0, y: track.minY))
            ctx.addLine(to: CGPoint(x: barH * 0.7, y: track.minY))
            ctx.addLine(to: CGPoint(x: barH * 0.7 + barH, y: track.maxY))
            ctx.addLine(to: CGPoint(x: barH, y: track.maxY))
            ctx.closePath()
            ctx.fillPath()
            ctx.restoreGState()
            x += barH * 2
        }
        ctx.restoreGState()

        Text.draw(stages[stage], in: ctx, at: CGPoint(x: 12, y: size.height - 10),
                  size: 8, color: CGColor(gray: 0.62, alpha: 1))
        Text.draw(String(format: "%.1f%%  -  %d SECONDS REMAINING", progress * 100, Int(eta)),
                  in: ctx, at: CGPoint(x: size.width - 12, y: size.height - 10),
                  size: 8, color: CGColor(gray: 0.45, alpha: 1), align: .right)
    }
}
