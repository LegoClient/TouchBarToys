import CoreGraphics
import Foundation
import ImageIO
import IOSurface
import UniformTypeIdentifiers

// Screenshots the Touch Bar itself, which `screencapture` cannot do: the DFR
// is not a CoreGraphics display and Cmd+Shift+6 needs Accessibility. It is a
// display stream though, and DFRFoundation will hand you one.
//
//   swiftc -O -o build/barshot Sources/Tools/barshot.swift
//   ./build/barshot out.png

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/touchbar.png"

let h = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)!
guard let sym = dlsym(h, "DFRDisplayStreamCreate") else { print("no symbol"); exit(1) }

typealias Handler = @convention(block) (Int32, UInt64, IOSurfaceRef?, AnyObject?) -> Void
typealias CreateFn = @convention(c) (Int32, DispatchQueue, Handler) -> Unmanaged<AnyObject>?
let create = unsafeBitCast(sym, to: CreateFn.self)

let queue = DispatchQueue(label: "dfr.capture")
var done = false
let sem = DispatchSemaphore(value: 0)

let handler: Handler = { status, _, surface, _ in
    guard !done, status == 0, let surface else { return }
    done = true
    IOSurfaceLock(surface, .readOnly, nil)
    let w = IOSurfaceGetWidth(surface)
    let ht = IOSurfaceGetHeight(surface)
    let bpr = IOSurfaceGetBytesPerRow(surface)
    let base = IOSurfaceGetBaseAddress(surface)
    print("frame: \(w)x\(ht) bytesPerRow=\(bpr) pixelFormat=\(IOSurfaceGetPixelFormat(surface))")
    if let ctx = CGContext(data: base, width: w, height: ht, bitsPerComponent: 8,
                           bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                     | CGBitmapInfo.byteOrder32Little.rawValue),
       let img = ctx.makeImage() {
        let url = URL(fileURLWithPath: outPath) as CFURL
        if let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, img, nil)
            CGImageDestinationFinalize(dest)
            print("wrote \(outPath)")
        }
    }
    IOSurfaceUnlock(surface, .readOnly, nil)
    sem.signal()
}

// The SDK marks these unavailable in favour of ScreenCaptureKit, but they
// still exist in CoreGraphics at runtime.
let cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)!
typealias StreamFn = @convention(c) (AnyObject) -> Int32
let start = unsafeBitCast(dlsym(cg, "CGDisplayStreamStart")!, to: StreamFn.self)
let stop = unsafeBitCast(dlsym(cg, "CGDisplayStreamStop")!, to: StreamFn.self)

guard let unmanaged = create(0, queue, handler) else { print("create returned nil"); exit(2) }
let stream = unmanaged.takeRetainedValue()
let started = start(stream)
print("CGDisplayStreamStart:", started == 0 ? "ok" : "err \(started)")
_ = sem.wait(timeout: .now() + 4)
_ = stop(stream)
print(done ? "captured" : "no frame arrived")
