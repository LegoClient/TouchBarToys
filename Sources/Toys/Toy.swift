import CoreGraphics
import CoreText
import Foundation

protocol Toy: AnyObject {
    /// Shown in the menu bar menu.
    var title: String { get }
    /// Shown as the Control Strip button glyph while this toy is selected.
    var emoji: String { get }
    func update(dt: Double, size: CGSize)
    func draw(in ctx: CGContext, size: CGSize)
    /// A tap on the canvas. `p` is in points, origin bottom-left.
    func tap(at p: CGPoint, size: CGSize)
}

extension Toy {
    func tap(at p: CGPoint, size: CGSize) {}
}

/// Base class for toys that render into a low-res `PixelBuffer` and let
/// CoreGraphics blow it up to Touch Bar size.
class PixelToy: Toy {
    var title: String { "?" }
    var emoji: String { "?" }
    /// Virtual canvas height in chunky pixels. Width follows the bar's aspect.
    var pixelHeight: Int { 20 }

    private var buf: PixelBuffer?

    final func buffer(for size: CGSize) -> PixelBuffer {
        let h = pixelHeight
        let aspect = size.height > 0 ? size.width / size.height : 33
        let w = max(1, Int((aspect * CGFloat(h)).rounded()))
        if let b = buf, b.width == w, b.height == h { return b }
        let b = PixelBuffer(width: w, height: h)
        buf = b
        resized(to: b)
        return b
    }

    /// Called when the pixel canvas is (re)allocated. Seed particles here.
    func resized(to buf: PixelBuffer) {}
    func update(dt: Double, size: CGSize) {}
    func renderPixels(into buf: PixelBuffer) {}
    func tap(at p: CGPoint, size: CGSize) {}

    func draw(in ctx: CGContext, size: CGSize) {
        let b = buffer(for: size)
        renderPixels(into: b)
        b.blit(into: ctx, rect: CGRect(origin: .zero, size: size))
    }
}

// MARK: - Crisp text on top of the chunky pixels

enum Text {
    static func draw(_ s: String, in ctx: CGContext, at p: CGPoint,
                     size: CGFloat, color: CGColor, bold: Bool = true,
                     align: CTTextAlignment = .left) {
        let font = CTFontCreateWithName((bold ? "Menlo-Bold" : "Menlo") as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: color,
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: s, attributes: attrs))
        var x = p.x
        if align != .left {
            let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            x -= align == .center ? w / 2 : w
        }
        ctx.saveGState()
        ctx.setShouldAntialias(true)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: x, y: p.y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    static func width(_ s: String, size: CGFloat, bold: Bool = true) -> CGFloat {
        let font = CTFontCreateWithName((bold ? "Menlo-Bold" : "Menlo") as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: s, attributes: [kCTFontAttributeName as NSAttributedString.Key: font]))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}

// MARK: - Deterministic-ish cheap RNG (Math.random but we own it)

struct RNG {
    private var s: UInt64
    init(seed: UInt64 = 0x9E37_79B9_7F4A_7C15) { s = seed | 1 }
    mutating func next() -> UInt64 {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17
        return s
    }
    mutating func d() -> Double { Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0) }
    mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * d() }
}

// MARK: - Registry

enum Toys {
    struct Group {
        let name: String
        let toys: [Toy]
    }

    static func groups() -> [Group] {
        [
            Group(name: "Classics", toys: [
                NyanToy(), DVDToy(), MatrixToy(), FireToy(), StarfieldToy(),
            ]),
            Group(name: "Made for the Strip", toys: [
                Rule110Toy(), LifeToy(), PendulumWaveToy(), TunnelToy(), MarqueeToy(),
            ]),
            Group(name: "Touch", toys: [
                SandToy(), RippleToy(), FireworksToy(), LightningToy(),
            ]),
            Group(name: "Games", toys: [
                FlappyToy(), DinoToy(), PongToy(), ReactionToy(),
            ]),
            Group(name: "Ambient", toys: [
                PlasmaToy(), MetaballsToy(), AquariumToy(), SnowToy(),
                AuroraToy(), MandelbrotToy(),
            ]),
            Group(name: "System", toys: [
                DashboardToy(), DashboardToy(style: .flat),
                CPUToy(), BatteryToy(), NetworkToy(), SystemToy(), ClockToy(),
            ]),
            Group(name: "Silly", toys: [
                HackerToy(), ProgressToy(), DominoToy(),
            ]),
        ]
    }

    static func all() -> [Toy] { groups().flatMap(\.toys) }
}
