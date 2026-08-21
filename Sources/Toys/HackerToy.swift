import CoreGraphics
import Foundation

/// A fake build/intrusion log, scrolling far too fast to read. Looks
/// tremendously busy. Does nothing.
final class HackerToy: PixelToy {
    override var title: String { "Hacker Terminal" }
    override var emoji: String { "💻" }
    override var pixelHeight: Int { 30 }

    private let verbs = ["LINKING", "PATCHING", "BYPASSING", "DECRYPTING", "SPOOFING",
                         "COMPILING", "INJECTING", "REROUTING", "HASHING", "SCANNING",
                         "MOUNTING", "FLUSHING", "SEEDING", "PROBING"]
    private let nouns = ["KERNEL", "MAINFRAME", "FIREWALL", "SUBNET", "PAYLOAD", "DAEMON",
                         "CIPHER", "SOCKET", "REGISTRY", "BUFFER", "GATEWAY", "SECTOR",
                         "PROXY", "HANDSHAKE"]
    private let tails = ["OK", "DONE", "0X4F2A", "42MS", "VERIFIED", "200", "SYNCED"]

    private var lines: [(text: String, hot: Bool)] = []
    private var acc = 0.0
    private var banner = 0.0
    private var rng = RNG(seed: 0xAC0F)
    private let rowH = 6

    override func resized(to buf: PixelBuffer) {
        lines = []
        for _ in 0..<(buf.height / rowH) { push() }
    }

    private func push() {
        let v = verbs[rng.int(verbs.count)]
        let n = nouns[rng.int(nouns.count)]
        let t = tails[rng.int(tails.count)]
        let addr = String(format: "%04X", rng.int(65536))
        lines.append((text: "[\(addr)] \(v) \(n) ... \(t)", hot: rng.d() < 0.12))
    }

    override func tap(at p: CGPoint, size: CGSize) { banner = 1.4 }

    override func update(dt: Double, size: CGSize) {
        let buf = buffer(for: size)
        banner = max(0, banner - dt)
        acc += dt
        while acc >= 0.09 {
            acc -= 0.09
            push()
            if lines.count > buf.height / rowH { lines.removeFirst() }
        }
    }

    override func renderPixels(into buf: PixelBuffer) {
        buf.clear(rgb(0, 8, 2))
        if banner > 0 {
            let flashing = Int(banner * 12) % 2 == 0
            buf.clear(flashing ? rgb(40, 0, 0) : rgb(0, 8, 2))
            let msg = "ACCESS GRANTED"
            let x = buf.width / 2 - MicroFont.width(msg) / 2
            MicroFont.draw(msg, into: buf, x: x, y: buf.height / 2 - 2,
                           color: flashing ? rgb(255, 90, 80) : rgb(255, 230, 220))
            return
        }
        for (i, line) in lines.enumerated() {
            let y = i * rowH
            let newest = i == lines.count - 1
            let color = line.hot ? rgb(255, 210, 90)
                : newest ? rgb(200, 255, 200) : rgb(30, 190, 60)
            MicroFont.draw(line.text, into: buf, x: 3, y: y, color: color)
        }
        // cursor block on the newest line
        let y = (lines.count - 1) * rowH
        if let last = lines.last, Int(acc * 12) % 2 == 0 {
            buf.fill(3 + MicroFont.width(last.text) + 2, y, 3, 5, rgb(160, 255, 160))
        }
    }
}
