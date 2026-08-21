import CoreGraphics
import Foundation

/// An LED dot-matrix scroller showing your own text.
///
/// Messages live in a plain text file, one per line, which is watched for
/// changes and reloaded live. A text file rather than an in-app editor because
/// AppKit text controls don't render in this app at all.
final class MarqueeToy: PixelToy {
    override var title: String { "LED Marquee" }
    override var emoji: String { "🪧" }
    override var pixelHeight: Int { 30 }

    static var textFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TouchBarToys/marquee.txt")
    }

    private static let defaultText = """
    TOUCH BAR TOYS  -  ALL SYSTEMS NOMINAL
    ONE MESSAGE PER LINE  -  TAP THE BAR TO CYCLE
    EDIT THIS FILE AND IT RELOADS BY ITSELF
    """

    /// Creates the file with a starter message the first time it's needed.
    @discardableResult
    static func ensureTextFile() -> URL {
        let url = textFileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? defaultText.write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    private var messages: [String] = []
    private var messageIndex = 0
    private var scroll = 0.0
    private var colorIndex = 0
    private var sinceCheck = 9.0
    private var loadedStamp: Date?

    private let dot = 5
    private let colors: [(UInt32, UInt32)] = [
        (rgb(255, 172, 40), rgb(46, 30, 6)),
        (rgb(255, 70, 60), rgb(48, 12, 10)),
        (rgb(80, 255, 130), rgb(8, 44, 20)),
        (rgb(120, 190, 255), rgb(10, 26, 46)),
    ]

    private var text: String {
        guard !messages.isEmpty else { return "SET YOUR TEXT FROM THE MENU BAR  -  " }
        return messages[messageIndex % messages.count] + "  -  "
    }

    private func reloadIfNeeded() {
        let url = Self.ensureTextFile()
        let stamp = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        guard stamp != loadedStamp else { return }
        loadedStamp = stamp
        let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        // The 3x5 font only has A-Z, 0-9 and a little punctuation.
        let lines = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
            .map { String($0.map { MicroFont.glyph($0) != nil ? $0 : " " }) }
        messages = lines.isEmpty ? [] : lines
        if messageIndex >= messages.count { messageIndex = 0 }
    }

    override func tap(at p: CGPoint, size: CGSize) {
        guard !messages.isEmpty else { return }
        messageIndex = (messageIndex + 1) % messages.count
        colorIndex = (colorIndex + 1) % colors.count
        scroll = 0
    }

    override func update(dt: Double, size: CGSize) {
        scroll += dt * 34
        sinceCheck += dt
        if sinceCheck >= 2 { sinceCheck = 0; reloadIfNeeded() }
    }

    override func renderPixels(into buf: PixelBuffer) {
        let (on, off) = colors[colorIndex]
        buf.clear(rgb(10, 8, 6))

        let rows = MicroFont.glyphH
        let cols = buf.width / dot + 2
        let topRow = (buf.height / dot - rows) / 2

        for r in 0..<rows {
            for c in 0..<cols { lamp(buf, c, topRow + r, off) }
        }

        let chars = Array(text)
        let charCells = MicroFont.glyphW + 1
        let totalCells = chars.count * charCells
        guard totalCells > 0 else { return }
        let offset = Int(scroll / Double(dot))

        for c in 0..<cols {
            let cell = ((c + offset) % totalCells + totalCells) % totalCells
            let charIndex = cell / charCells
            let colInChar = cell % charCells
            guard colInChar < MicroFont.glyphW,
                  let glyph = MicroFont.glyph(chars[charIndex]) else { continue }
            for (r, d) in glyph.utf8.enumerated() {
                let bits = Int(d) - 48
                if bits & (4 >> colInChar) != 0 { lamp(buf, c, topRow + r, on) }
            }
        }
    }

    private func lamp(_ b: PixelBuffer, _ col: Int, _ row: Int, _ color: UInt32) {
        b.fill(col * dot, row * dot, dot - 1, dot - 1, color)
    }
}
