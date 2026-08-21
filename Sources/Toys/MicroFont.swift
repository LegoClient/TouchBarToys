import Foundation

/// A 3x5 pixel font. Each glyph is five octal digits; each digit is one row,
/// bit 2 = leftmost column. Just enough for scores, counters and matrix rain.
enum MicroFont {
    static let glyphW = 3
    static let glyphH = 5

    private static let table: [Character: String] = [
        "0": "75557", "1": "26227", "2": "71747", "3": "71717", "4": "55711",
        "5": "74717", "6": "74757", "7": "71111", "8": "75757", "9": "75717",
        "A": "75755", "B": "65656", "C": "74447", "D": "65556", "E": "74747",
        "F": "74744", "G": "74557", "H": "55755", "I": "72227", "J": "11157",
        "K": "55655", "L": "44447", "M": "57755", "N": "65555", "O": "75557",
        "P": "75744", "Q": "75571", "R": "75655", "S": "74717", "T": "72222",
        "U": "55557", "V": "55552", "W": "55775", "X": "55255", "Y": "55222",
        "Z": "71247",
        ":": "02020", "-": "00700", ".": "00002", "%": "51245", "/": "11244",
        "!": "22202", "+": "02720", " ": "00000",
    ]

    /// Every character the font can actually draw, handy for random glyph soup.
    static let alphabet: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    static func glyph(_ c: Character) -> String? {
        table[Character(String(c).uppercased())]
    }

    /// Draw one glyph with its top-left at (x, y).
    static func draw(_ c: Character, into b: PixelBuffer, x: Int, y: Int, color: UInt32) {
        guard let g = glyph(c) else { return }
        for (row, d) in g.utf8.enumerated() {
            let bits = Int(d) - 48
            if bits & 4 != 0 { b.px(x,     y + row, color) }
            if bits & 2 != 0 { b.px(x + 1, y + row, color) }
            if bits & 1 != 0 { b.px(x + 2, y + row, color) }
        }
    }

    static func draw(_ s: String, into b: PixelBuffer, x: Int, y: Int,
                     color: UInt32, spacing: Int = 1) {
        var cx = x
        for c in s {
            draw(c, into: b, x: cx, y: y, color: color)
            cx += glyphW + spacing
        }
    }

    static func width(_ s: String, spacing: Int = 1) -> Int {
        s.isEmpty ? 0 : s.count * (glyphW + spacing) - spacing
    }
}
