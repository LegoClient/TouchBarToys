import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Offscreen preview harness: renders every toy to PNG at Touch Bar geometry so
// the pixel art can be checked without a Touch Bar in the loop.

let barSize = CGSize(width: 1004, height: 30)
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./preview"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func newContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                        | CGBitmapInfo.byteOrder32Little.rawValue)!
}

func writePNG(_ image: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

/// Render `frames` snapshots of a toy, stacked vertically, magnified `scale`x.
func sheet(_ toy: Toy, frames: [Double], scale: CGFloat, crop: CGRect? = nil) -> CGImage {
    let region = crop ?? CGRect(origin: .zero, size: barSize)
    let gap: CGFloat = 4
    let w = Int(region.width * scale)
    let rowH = region.height * scale
    let h = Int(rowH * CGFloat(frames.count) + gap * CGFloat(frames.count - 1))
    let out = newContext(w, h)
    out.setFillColor(CGColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1))
    out.fill(CGRect(x: 0, y: 0, width: w, height: h))

    var elapsed = 0.0
    let dt = 1.0 / 60.0
    var frameImages: [CGImage] = []
    for target in frames {
        while elapsed < target {
            toy.update(dt: dt, size: barSize)
            elapsed += dt
        }
        let bar = newContext(Int(barSize.width), Int(barSize.height))
        toy.draw(in: bar, size: barSize)
        if let img = bar.makeImage() {
            let cropped = crop.flatMap { img.cropping(to: $0) } ?? img
            frameImages.append(cropped)
        }
    }
    for (i, img) in frameImages.enumerated() {
        let y = CGFloat(h) - rowH * CGFloat(i + 1) - gap * CGFloat(i)
        out.interpolationQuality = .none
        out.draw(img, in: CGRect(x: 0, y: y, width: CGFloat(w), height: rowH))
    }
    return out.makeImage()!
}

let benching = CommandLine.arguments.contains("--bench")
for toy in (benching ? [] : Toys.all()) {
    let slug = toy.title
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    // A tap partway through, so tap-driven toys show their reaction.
    toy.tap(at: CGPoint(x: barSize.width * 0.5, y: 15), size: barSize)
    let full = sheet(toy, frames: [0.6, 1.4, 2.2, 3.0], scale: 2)
    writePNG(full, "\(outDir)/\(slug).png")

    // A magnified crop so individual pixels are inspectable.
    let fresh = Toys.all().first { $0.title == toy.title }!
    let zoomX = fresh is NyanToy ? barSize.width * 0.55 : barSize.width * 0.20
    let zoom = sheet(fresh, frames: [0.7, 1.1, 1.5, 1.9],
                     scale: 7,
                     crop: CGRect(x: zoomX, y: 0, width: 150, height: 30))
    writePNG(zoom, "\(outDir)/\(slug)-zoom.png")
    print("rendered \(slug)")
}
if !benching { print("output: \(outDir)") }

// --- bench: how expensive is each toy per frame at Touch Bar geometry? -------
if CommandLine.arguments.contains("--bench") {
    print("\nper-frame cost at \(Int(barSize.width))x\(Int(barSize.height)), 300 frames:")
    for toy in Toys.all() {
        let ctx = newContext(Int(barSize.width), Int(barSize.height))
        for _ in 0..<30 { toy.update(dt: 1.0 / 30, size: barSize); toy.draw(in: ctx, size: barSize) }
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<300 {
            toy.update(dt: 1.0 / 30, size: barSize)
            toy.draw(in: ctx, size: barSize)
        }
        let ms = (CFAbsoluteTimeGetCurrent() - start) / 300 * 1000
        let load = ms / (1000.0 / 30.0) * 100
        print(String(format: "  %-22s %5.2f ms  (%4.1f%% of one core at 30fps)",
                     (toy.title as NSString).utf8String!, ms, load))
    }
}

// --- contact sheets, one per group, so each stays legible -------------------
if !benching {
    for group in Toys.groups() {
        let scale: CGFloat = 2
        let rowH = barSize.height * scale
        let gap: CGFloat = 12
        let all = group.toys
        let sheetW = Int(barSize.width * scale)
        let sheetH = Int((rowH + gap) * CGFloat(all.count) + gap)
        let out = newContext(sheetW, sheetH)
        out.setFillColor(CGColor(gray: 0.09, alpha: 1))
        out.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
        for (i, toy) in all.enumerated() {
            for k in 0..<180 {
                toy.update(dt: 1.0 / 60, size: barSize)
                if k == 60 { toy.tap(at: CGPoint(x: barSize.width * 0.45, y: 15), size: barSize) }
            }
            let bar = newContext(Int(barSize.width), Int(barSize.height))
            toy.draw(in: bar, size: barSize)
            guard let img = bar.makeImage() else { continue }
            let y = CGFloat(sheetH) - (rowH + gap) * CGFloat(i + 1)
            out.interpolationQuality = .none
            out.draw(img, in: CGRect(x: 0, y: y, width: CGFloat(sheetW), height: rowH))
            Text.draw(toy.title, in: out, at: CGPoint(x: 10, y: y - 10),
                      size: 12, color: CGColor(gray: 0.66, alpha: 1))
        }
        let slug = group.name.lowercased().replacingOccurrences(of: " ", with: "-")
        writePNG(out.makeImage()!, "\(outDir)/sheet-\(slug).png")
        print("sheet: \(slug)")
    }
}
