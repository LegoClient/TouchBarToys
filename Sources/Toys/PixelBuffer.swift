import CoreGraphics

@inline(__always) func rgb(_ r: Int, _ g: Int, _ b: Int) -> UInt32 {
    0xFF00_0000 | UInt32(r & 255) << 16 | UInt32(g & 255) << 8 | UInt32(b & 255)
}

/// A tiny chunky-pixel canvas. Toys plot into this and it gets blitted onto the
/// Touch Bar with nearest-neighbour scaling, which is what makes everything
/// look like a 1998 screensaver instead of smooth vector art.
final class PixelBuffer {
    let width: Int
    let height: Int
    let data: UnsafeMutablePointer<UInt32>
    private let ctx: CGContext

    init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
        let count = self.width * self.height
        data = UnsafeMutablePointer<UInt32>.allocate(capacity: count)
        data.initialize(repeating: 0xFF00_0000, count: count)
        ctx = CGContext(data: data,
                        width: self.width, height: self.height,
                        bitsPerComponent: 8, bytesPerRow: self.width * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                  | CGBitmapInfo.byteOrder32Little.rawValue)!
    }

    deinit { data.deallocate() }

    func clear(_ c: UInt32 = 0xFF00_0000) {
        data.update(repeating: c, count: width * height)
    }

    @inline(__always) func px(_ x: Int, _ y: Int, _ c: UInt32) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        data[y * width + x] = c
    }

    @inline(__always) func get(_ x: Int, _ y: Int) -> UInt32 {
        guard x >= 0, x < width, y >= 0, y < height else { return 0xFF00_0000 }
        return data[y * width + x]
    }

    /// Alpha-blend `c` (0...1 alpha) over what's already there.
    @inline(__always) func blend(_ x: Int, _ y: Int, _ c: UInt32, _ a: Double) {
        guard x >= 0, x < width, y >= 0, y < height, a > 0 else { return }
        if a >= 1 { data[y * width + x] = c; return }
        let d = data[y * width + x]
        let sr = Double((c >> 16) & 255), sg = Double((c >> 8) & 255), sb = Double(c & 255)
        let dr = Double((d >> 16) & 255), dg = Double((d >> 8) & 255), db = Double(d & 255)
        data[y * width + x] = rgb(Int(dr + (sr - dr) * a),
                                  Int(dg + (sg - dg) * a),
                                  Int(db + (sb - db) * a))
    }

    func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: UInt32) {
        guard w > 0, h > 0 else { return }
        let x0 = max(0, x), x1 = min(width, x + w)
        let y0 = max(0, y), y1 = min(height, y + h)
        guard x0 < x1, y0 < y1 else { return }
        for yy in y0..<y1 {
            let row = yy * width
            for xx in x0..<x1 { data[row + xx] = c }
        }
    }

    /// Outlined rectangle: 1px border of `stroke`, interior `fill`.
    func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int, fill f: UInt32, stroke s: UInt32) {
        fill(x, y, w, h, s)
        fill(x + 1, y + 1, w - 2, h - 2, f)
    }

    func image() -> CGImage? { ctx.makeImage() }

    /// Blit into a real CGContext, nearest-neighbour, filling `rect`.
    func blit(into ctx: CGContext, rect: CGRect) {
        guard let img = image() else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.draw(img, in: rect)
        ctx.restoreGState()
    }
}
