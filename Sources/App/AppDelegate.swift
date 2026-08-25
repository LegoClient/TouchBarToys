import AppKit

extension NSTouchBarItem.Identifier {
    static let strip  = NSTouchBarItem.Identifier("com.touchbartoys.app.strip")
    static let canvas = NSTouchBarItem.Identifier("com.touchbartoys.app.canvas")
    static let close  = NSTouchBarItem.Identifier("com.touchbartoys.app.close")
    static let prev   = NSTouchBarItem.Identifier("com.touchbartoys.app.prev")
    static let next   = NSTouchBarItem.Identifier("com.touchbartoys.app.next")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {

    private var toys: [Toy] = Toys.all()
    private var index = 0
    private var toy: Toy { toys[index] }

    private var statusItem: NSStatusItem!
    private var stripItem: NSCustomTouchBarItem!
    private var stripButton: BarButtonView!
    private var canvasView: ToyView!
    private var modalBar: NSTouchBar?
    private var isPresented = false
    /// What the user asked for, as opposed to what the Touch Bar currently
    /// shows. `isPresented` gets cleared when the system takes the bar back,
    /// so it can't be used to decide whether a retry is wanted.
    private var wantsBar = false
    private var canvasWidthConstraint: NSLayoutConstraint?
    private var devMode = false
    private var menu = NSMenu()

    /// A nib-less app has no main menu. Without one, macOS 26 draws status-item
    /// menu rows with no text at all. Separators and checkmarks still render,
    /// which is exactly the "blank menu" symptom.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Touch Bar Toys",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        NSApp.mainMenu = main
    }

    /// Width left for the canvas once the ✕ ◀ ▶ buttons take their share, and
    /// the wider value used in full-screen mode where there are no buttons.
    /// Both are overridable while tuning against a real bar.
    private var widthWithButtons: CGFloat =
        ProcessInfo.processInfo.environment["TBT_CANVAS_WIDTH"].flatMap { Double($0) }
            .map { CGFloat($0) } ?? 812
    private var widthFullScreen: CGFloat =
        ProcessInfo.processInfo.environment["TBT_FULL_WIDTH"].flatMap { Double($0) }
            .map { CGFloat($0) } ?? 1004

    /// 1004pt is the width of the bar itself, measured from a `barshot`
    /// capture (2008 physical pixels at 2x). The zero-frames check can't
    /// calibrate this one: with a single item the bar clips an oversize canvas
    /// rather than refusing to lay it out, so even 1400pt "draws fine" while
    /// running off the edge. An earlier guess of 1050 did exactly that, and
    /// pushed the panel's close button off the end.
    private var fullScreen: Bool { defaults.bool(forKey: fullScreenKey) }

    /// The width in use for the current mode. Shrinking on a failed layout has
    /// to stick to the mode it was measured in.
    private var activeWidth: CGFloat {
        get { fullScreen ? widthFullScreen : widthWithButtons }
        set { if fullScreen { widthFullScreen = newValue } else { widthWithButtons = newValue } }
    }

    private let defaults = UserDefaults.standard
    private let toyKey = "selectedToy"
    private let stripKey = "showInControlStrip"
    private let fullScreenKey = "fullScreen"
    private let doubleTapKey = "doubleTapControls"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        devMode = CommandLine.arguments.contains("--diag")
        Log.startSession("pid \(ProcessInfo.processInfo.processIdentifier)")
        installMainMenu()

        let missing = TouchBarSPI.missing
        guard missing.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Touch Bar Toys can't run on this macOS"
            alert.informativeText =
                "These private Touch Bar entry points are gone:\n\n" +
                missing.joined(separator: "\n")
            alert.alertStyle = .critical
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        if let saved = defaults.string(forKey: toyKey),
           let i = toys.firstIndex(where: { $0.title == saved }) {
            index = i
        }
        if defaults.object(forKey: stripKey) == nil {
            defaults.set(true, forKey: stripKey)
        }
        if defaults.object(forKey: doubleTapKey) == nil {
            defaults.set(true, forKey: doubleTapKey)
        }

        canvasView = ToyView(toy: toy)
        canvasView.doubleTapEnabled = defaults.bool(forKey: doubleTapKey)
        canvasView.onWindowChange = { [weak self] attached in
            Log.write("canvas window \(attached ? "attached" : "detached")")
            guard let self, !attached else { return }
            // Could be a transient detach while re-presenting; confirm next turn.
            DispatchQueue.main.async {
                if self.canvasView.window == nil { self.isPresented = false }
            }
        }
        buildStatusItem()
        installStripItem()
        DFR.showsCloseBoxWhenFrontMost(true)

        if CommandLine.arguments.contains("--selftest") { runSelfTest() }
        if CommandLine.arguments.contains("--diag") { runDiag() }
        if CommandLine.arguments.contains("--menushot") { runMenuShot() }
        if CommandLine.arguments.contains("--fontprobe") { runFontProbe() }
        if CommandLine.arguments.contains("--menumock") { runMenuMock() }
        if CommandLine.arguments.contains("--testmenu") { runMenuActionTest() }
        if CommandLine.arguments.contains("--buttonshot") { runButtonShot() }
        if CommandLine.arguments.contains("--testbuttons") { runButtonWiringTest() }
        if CommandLine.arguments.contains("--controls") { runControlsTest() }
        if CommandLine.arguments.contains("--testgesture") { runGestureTest() }
        if CommandLine.arguments.contains("--present") { runPresentMode() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        canvasView?.stop()
        dismiss()
        if !devMode { DFR.setControlStripPresence(.strip, false) }
    }

    /// Drives the whole Touch Bar path headlessly and reports what happened,
    /// so the plumbing can be verified without a Touch Bar screenshot.
    private func runSelfTest() {
        print("SPI probes:            all present")
        print("control strip item:    added as \(NSTouchBarItem.Identifier.strip.rawValue)")
        present()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            let onBar = self.canvasView.window != nil
            print("modal bar presented:   \(self.isPresented)")
            print("canvas has a window:   \(onBar)")
            print("canvas size:           \(self.canvasView.bounds.size)")
            print("frames drawn in 3s:    \(self.canvasView.framesDrawn)")
            print("current toy:           \(self.toy.title)")
            print(onBar && self.canvasView.framesDrawn > 30
                  ? "RESULT: live on the Touch Bar"
                  : "RESULT: FAILED - canvas never made it onto the bar")
            self.dismiss()
            DFR.setControlStripPresence(.strip, false)
            NSApp.terminate(nil)
        }
    }

    /// Pops the status menu open, then renders every on-screen window of this
    /// process into a PNG via cacheDisplay, an in-process capture, so it needs
    /// no Screen Recording permission.
    private func runMenuShot() {
        devMode = true
        let t = Timer(timeInterval: 1.5, repeats: false) { _ in
            self.captureWindows()
            self.menu.cancelTracking()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
        }
        // .common so it fires inside the menu's own tracking run-loop mode.
        RunLoop.main.add(t, forMode: .common)
        DispatchQueue.main.async {
            self.menu.popUp(positioning: nil, at: NSPoint(x: 500, y: 700), in: nil)
        }
    }

    private func captureWindows() {
        print("NSApp.windows: \(NSApp.windows.count)")
        for (i, w) in NSApp.windows.enumerated() {
            print("  [\(i)] \(type(of: w)) visible=\(w.isVisible) alpha=\(w.alphaValue) frame=\(w.frame)")
            guard w.isVisible, let cv = w.contentView,
                  cv.bounds.width > 4, cv.bounds.height > 4,
                  let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) else { continue }
            cv.cacheDisplay(in: cv.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                let path = "/tmp/tbt-window-\(i).png"
                try? data.write(to: URL(fileURLWithPath: path))
                print("        -> \(path)  \(rep.pixelsWide)x\(rep.pixelsHigh)  subviews=\(cv.subviews.count)")
            }
        }
    }

    /// Renders the menu rows into an offscreen bitmap. cacheDisplay on a live
    /// menu window drops text, so this is how the row drawing gets checked.
    /// Opens the real menu, fires "Show on Touch Bar" through the real row
    /// action path, and checks the bar actually came up afterwards.
    /// Presents the bar, then fires the live buttons' tap handlers and checks
    /// they actually did something. This tests the wiring, not touch delivery,
    /// synthesising a Touch Bar touch needs permissions this process lacks.
    private func runButtonWiringTest() {
        devMode = true
        present()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard let bar = self.modalBar,
                  let nextView = (bar.item(forIdentifier: .next) as? NSCustomTouchBarItem)?.view as? BarButtonView,
                  let closeView = (bar.item(forIdentifier: .close) as? NSCustomTouchBarItem)?.view as? BarButtonView
            else { print("RESULT: FAILED - buttons not found on the presented bar"); NSApp.terminate(nil); return }

            let before = self.toy.title
            print("next button: onTap wired = \(nextView.onTap != nil)")
            nextView.onTap?()
            let after = self.toy.title
            print("toy: \(before) -> \(after)")

            let framesBefore = self.canvasView.framesDrawn
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let stillDrawing = self.canvasView.framesDrawn > framesBefore
                print("still drawing after switch: \(stillDrawing)")
                print("close button: onTap wired = \(closeView.onTap != nil)")
                closeView.onTap?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let closed = !self.isPresented && self.canvasView.window == nil
                    print("closed: \(closed)")
                    print(before != after && stillDrawing && closed
                          ? "RESULT: buttons wired correctly"
                          : "RESULT: FAILED")
                    NSApp.terminate(nil)
                }
            }
        }
    }

    /// Presents the bar and holds it, so `barshot` can photograph it.
    /// `--present <seconds> [--panel]` then exits.
    private func runPresentMode() {
        devMode = true
        let args = CommandLine.arguments
        let seconds = args.firstIndex(of: "--present").flatMap { i -> Double? in
            i + 1 < args.count ? Double(args[i + 1]) : nil
        } ?? 12
        if let name = args.firstIndex(of: "--toy").flatMap({ i -> String? in
            i + 1 < args.count ? args[i + 1] : nil
        }), let idx = toys.firstIndex(where: { $0.title.lowercased().contains(name.lowercased()) }) {
            select(idx)
        }
        present()
        if args.contains("--panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let mid = CGPoint(x: self.canvasView.bounds.midX, y: 15)
                self.canvasView.began(at: mid)
                self.canvasView.began(at: mid)
                Log.write("present mode: opened control panel")
            }
        }
        print("holding the bar for \(seconds)s with \(toy.title)")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            self.dismiss()
            NSApp.terminate(nil)
        }
    }

    /// Exercises the double-tap gesture through the real input path. Touch Bar
    /// touches can't be synthesised from here, so this drives the same entry
    /// point the touch handlers call.
    private func runGestureTest() {
        devMode = true
        canvasView.setFrameSize(NSSize(width: 812, height: 30))
        canvasView.doubleTapEnabled = true
        var failures = 0
        func check(_ label: String, _ got: Bool, _ want: Bool) {
            let ok = got == want
            if !ok { failures += 1 }
            print("  \(ok ? "ok  " : "FAIL") \(label): showControls=\(got), expected \(want)")
        }
        let mid = CGPoint(x: 400, y: 15)

        print("two taps 80ms apart should open it")
        canvasView.began(at: mid)
        Thread.sleep(forTimeInterval: 0.08)
        canvasView.began(at: mid)
        check("after fast double tap", canvasView.showControls, true)

        print("two taps 500ms apart should not close it")
        canvasView.began(at: CGPoint(x: 300, y: 15))
        Thread.sleep(forTimeInterval: 0.5)
        canvasView.began(at: CGPoint(x: 300, y: 15))
        check("after slow taps", canvasView.showControls, true)

        print("a second fast double tap should close it")
        canvasView.began(at: CGPoint(x: 120, y: 15))
        Thread.sleep(forTimeInterval: 0.08)
        canvasView.began(at: CGPoint(x: 120, y: 15))
        check("after second double tap", canvasView.showControls, false)

        print("taps far apart in space should not count as a double tap")
        canvasView.began(at: CGPoint(x: 100, y: 15))
        Thread.sleep(forTimeInterval: 0.08)
        canvasView.began(at: CGPoint(x: 700, y: 15))
        check("after spread-out taps", canvasView.showControls, false)

        print("the close button should dismiss it")
        canvasView.began(at: mid)
        Thread.sleep(forTimeInterval: 0.08)
        canvasView.began(at: mid)
        canvasView.began(at: CGPoint(x: 812 - 21, y: 15))   // the X
        check("after tapping close", canvasView.showControls, false)

        print("with the gesture disabled, double tapping does nothing")
        canvasView.doubleTapEnabled = false
        canvasView.began(at: mid)
        Thread.sleep(forTimeInterval: 0.08)
        canvasView.began(at: mid)
        check("gesture off", canvasView.showControls, false)

        print(failures == 0 ? "RESULT: gesture behaves" : "RESULT: FAILED (\(failures))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
    }

    /// Reads brightness and volume, nudges each by 1% to prove the write path
    /// works, restores the original value, then renders the panel to a PNG.
    private func runControlsTest() {
        devMode = true
        print("brightness available: \(SystemControls.brightnessAvailable)")
        print("volume available:     \(SystemControls.volumeAvailable)")

        let b0 = SystemControls.brightness
        let v0 = SystemControls.volume
        let m0 = SystemControls.muted
        print(String(format: "read   brightness=%.3f volume=%.3f muted=%@", b0, v0,
                     m0 ? "yes" : "no"))

        let bTest = min(0.95, max(SystemControls.minimumBrightness, b0 + 0.01))
        SystemControls.brightness = bTest
        let bBack = SystemControls.brightness
        SystemControls.brightness = b0
        print(String(format: "write  brightness %.3f -> read back %.3f  (%@), restored to %.3f",
                     bTest, bBack, abs(bBack - bTest) < 0.02 ? "OK" : "MISMATCH",
                     SystemControls.brightness))

        let vTest = min(0.95, max(0.0, v0 + 0.01))
        SystemControls.volume = vTest
        let vBack = SystemControls.volume
        SystemControls.volume = v0
        SystemControls.muted = m0
        print(String(format: "write  volume     %.3f -> read back %.3f  (%@), restored to %.3f",
                     vTest, vBack, abs(vBack - vTest) < 0.02 ? "OK" : "MISMATCH",
                     SystemControls.volume))

        // draw the panel offscreen at both bar widths
        for (name, width) in [("buttons", 812.0), ("fullscreen", 1050.0)] {
            let size = CGSize(width: width, height: 30)
            let scale: CGFloat = 2
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                             pixelsWide: Int(size.width * scale),
                                             pixelsHigh: Int(size.height * scale),
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                             isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0),
                  let g = NSGraphicsContext(bitmapImageRep: rep) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = g
            g.cgContext.scaleBy(x: scale, y: scale)
            g.cgContext.setFillColor(CGColor(gray: 0.04, alpha: 1))
            g.cgContext.fill(CGRect(origin: .zero, size: size))
            let panel = ControlPanel()
            panel.refresh()
            panel.draw(in: g.cgContext, size: size)
            NSGraphicsContext.restoreGraphicsState()
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/tbt-panel-\(name).png"))
                print("wrote /tmp/tbt-panel-\(name).png")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
    }

    /// Renders the drawn buttons offscreen so they can actually be looked at.
    private func runButtonShot() {
        devMode = true
        let kinds: [(String, BarButtonView.Kind, CGFloat)] =
            [("close", .close, 52), ("next", .next, 52), ("rainbow", .rainbow, 58)]
        let gap: CGFloat = 8
        let totalW = kinds.reduce(gap) { $0 + $1.2 + gap }
        let scale: CGFloat = 4
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(totalW * scale), pixelsHigh: Int(46 * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let g = NSGraphicsContext(bitmapImageRep: out) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = g
        g.cgContext.scaleBy(x: scale, y: scale)
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: totalW, height: 46).fill()
        var x = gap
        for (name, kind, w) in kinds {
            let v = BarButtonView(kind: kind, width: w)
            v.setFrameSize(NSSize(width: w, height: 30))
            g.saveGraphicsState()
            g.cgContext.translateBy(x: x, y: 8)
            v.draw(v.bounds)
            g.restoreGraphicsState()
            print("drew \(name) at x=\(x) w=\(w)")
            x += w + gap
        }
        NSGraphicsContext.restoreGraphicsState()
        if let data = out.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/tbt-buttons.png"))
            print("wrote /tmp/tbt-buttons.png")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
    }

    private func runMenuActionTest() {
        devMode = true
        let fire = Timer(timeInterval: 1.2, repeats: false) { _ in
            guard let item = self.menu.items.first(where: { $0.title == "Show on Touch Bar" }),
                  let row = item.view as? MenuRowView else {
                print("RESULT: FAILED - could not find the row"); NSApp.terminate(nil); return
            }
            print("clicking 'Show on Touch Bar' via the real row action path")
            row.performAction()
            let check = Timer(timeInterval: 3.0, repeats: false) { _ in
                let ok = self.isPresented && self.canvasView.window != nil
                    && self.canvasView.framesDrawn > 30
                print("isPresented:           \(self.isPresented)")
                print("canvas has a window:   \(self.canvasView.window != nil)")
                print("canvas size:           \(self.canvasView.bounds.size)")
                print("frames drawn:          \(self.canvasView.framesDrawn)")
                print(ok ? "RESULT: menu item opened the bar"
                         : "RESULT: FAILED - menu item did not open the bar")
                self.dismiss()
                NSApp.terminate(nil)
            }
            RunLoop.main.add(check, forMode: .common)
        }
        RunLoop.main.add(fire, forMode: .common)
        DispatchQueue.main.async {
            self.menu.popUp(positioning: nil, at: NSPoint(x: 500, y: 700), in: nil)
        }
    }

    private func runMenuMock() {
        devMode = true
        let rows = menu.items
        let width = rows.compactMap { ($0.view as? MenuRowView)?.frame.width }.max() ?? 200
        let sepH: CGFloat = 9
        let total = rows.reduce(CGFloat(0)) { $0 + ($1.isSeparatorItem ? sepH : ($1.view?.frame.height ?? 22)) } + 12
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(width * scale), pixelsHigh: Int(total * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let g = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = g
        g.cgContext.scaleBy(x: scale, y: scale)
        NSColor.windowBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: width, height: total).fill()

        var y = total - 6
        for item in rows {
            if item.isSeparatorItem {
                y -= sepH
                NSColor.separatorColor.setFill()
                NSRect(x: 10, y: y + sepH / 2, width: width - 20, height: 1).fill()
                continue
            }
            guard let v = item.view as? MenuRowView else { continue }
            y -= v.frame.height
            v.forcedState = item.state
            g.saveGraphicsState()
            g.cgContext.translateBy(x: 0, y: y)
            v.draw(v.bounds)
            g.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/tbt-menu-mock.png"))
            print("wrote /tmp/tbt-menu-mock.png \(rep.pixelsWide)x\(rep.pixelsHigh)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
    }

    private func runFontProbe() {
        devMode = true
        func probe(_ label: String, _ font: NSFont?) {
            guard let font else { print(String(format: "  %-26s <nil>", (label as NSString).utf8String!)); return }
            let ct = font as CTFont
            var chars = Array("Hamburg".utf16)
            var glyphs = [CGGlyph](repeating: 0, count: chars.count)
            let ok = CTFontGetGlyphsForCharacters(ct, &chars, &glyphs, chars.count)
            let measured = NSAttributedString(string: "Hamburg", attributes: [.font: font]).size().width
            print(String(format: "  %-26s glyphs=%@ ids=%@ width=%.1f  ps=%@",
                         (label as NSString).utf8String!,
                         ok ? "OK" : "FAIL", "\(glyphs.prefix(4))", measured,
                         CTFontCopyPostScriptName(ct) as String))
        }
        print("font probe (process = \(ProcessInfo.processInfo.processIdentifier)):")
        probe("NSFont.menuFont(0)", .menuFont(ofSize: 0))
        probe("NSFont.systemFont(13)", .systemFont(ofSize: 13))
        probe("NSFont.messageFont(13)", .messageFont(ofSize: 13))
        probe("Menlo 13", NSFont(name: "Menlo", size: 13))
        probe("Helvetica 13", NSFont(name: "Helvetica", size: 13))
        probe("HelveticaNeue 13", NSFont(name: "HelveticaNeue", size: 13))
        // Glyph lookup succeeding says nothing about rasterisation, so draw into
        // an offscreen bitmap and count actual ink.
        func ink(_ label: String, _ draw: (NSGraphicsContext) -> Void) {
            let w = 260, h = 40
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                             isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0),
                  let g = NSGraphicsContext(bitmapImageRep: rep) else { return }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = g
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)).fill()
            draw(g)
            g.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            var dark = 0
            if let d = rep.bitmapData {
                for i in stride(from: 0, to: w * h * 4, by: 4) where d[i] < 200 { dark += 1 }
            }
            print(String(format: "  %-28s ink=%d px", (label as NSString).utf8String!, dark))
        }
        ink("NSAttributedString sysfont") { _ in
            NSAttributedString(string: "Hamburg", attributes: [
                .font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.black,
            ]).draw(at: NSPoint(x: 6, y: 10))
        }
        ink("NSAttributedString Menlo") { _ in
            NSAttributedString(string: "Hamburg", attributes: [
                .font: NSFont(name: "Menlo", size: 13)!, .foregroundColor: NSColor.black,
            ]).draw(at: NSPoint(x: 6, y: 10))
        }
        ink("NSString drawAtPoint") { _ in
            ("Hamburg" as NSString).draw(at: NSPoint(x: 6, y: 10), withAttributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black,
            ])
        }
        ink("CTLineDraw sysfont") { g in
            let f = NSFont.menuFont(ofSize: 0) as CTFont
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Hamburg",
                attributes: [kCTFontAttributeName as NSAttributedString.Key: f,
                             kCTForegroundColorAttributeName as NSAttributedString.Key: NSColor.black.cgColor]))
            g.cgContext.textPosition = CGPoint(x: 6, y: 10)
            CTLineDraw(line, g.cgContext)
        }
        ink("emoji sysfont (control)") { _ in
            NSAttributedString(string: "🌈", attributes: [
                .font: NSFont.menuFont(ofSize: 0),
            ]).draw(at: NSPoint(x: 6, y: 10))
        }
        ink("plain rect (control)") { g in
            NSColor.black.setFill()
            NSRect(x: 6, y: 10, width: 20, height: 12).fill()
        }
        print("bundle localizations:   \(Bundle.main.localizations)")
        print("preferredLocalizations: \(Bundle.main.preferredLocalizations)")
        print("developmentRegion:      \(Bundle.main.developmentLocalization ?? "<nil>")")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
    }

    private func runDiag() {
        func dump(_ label: String, _ c: NSColor) {
            let s = c.usingColorSpace(.sRGB)
            print(String(format: "  %-22s r=%.2f g=%.2f b=%.2f a=%.2f", (label as NSString).utf8String!,
                         s?.redComponent ?? -1, s?.greenComponent ?? -1,
                         s?.blueComponent ?? -1, s?.alphaComponent ?? -1))
        }
        print("appearance:            \(NSApp.effectiveAppearance.name.rawValue)")
        print("NSApp.mainMenu:        \(NSApp.mainMenu == nil ? "nil" : "set")")
        print("menu font:             \(NSFont.menuFont(ofSize: 0))")
        print("colors:")
        dump("labelColor", .labelColor)
        dump("controlTextColor", .controlTextColor)
        dump("selectedMenuItemText", .selectedMenuItemTextColor)
        print("menu items:            \(menu.numberOfItems)")
        for it in menu.items {
            print(String(format: "  [%@] title=%@ hidden=%@ enabled=%@ attr=%@",
                         it.isSeparatorItem ? "sep" : "itm",
                         it.title.isEmpty ? "<EMPTY>" : it.title,
                         it.isHidden ? "y" : "n", it.isEnabled ? "y" : "n",
                         it.attributedTitle == nil ? "nil" : "set"))
        }
        print("status button title:   \(statusItem.button?.title ?? "<nil>")")
        let sid = NSTouchBarItem.Identifier.strip.rawValue
        print("strip customised:      \(ControlStrip.isCustomised)")
        print("strip list has us:     \(ControlStrip.contains(sid))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
    }

    // MARK: - Control Strip

    private func installStripItem() {
        stripButton = BarButtonView(kind: .rainbow, width: 58)
        stripButton.onTap = { [weak self] in self?.stripTapped() }

        stripItem = NSCustomTouchBarItem(identifier: .strip)
        stripItem.view = stripButton
        NSTouchBarItem.addSystemTrayItem(stripItem)

        let pinned = defaults.bool(forKey: stripKey)
        DFR.setControlStripPresence(.strip, pinned)
        if pinned { ControlStrip.setPinned(NSTouchBarItem.Identifier.strip.rawValue, true) }
    }

    @objc private func stripTapped() {
        Log.write("stripTapped isPresented=\(isPresented)")
        isPresented ? dismiss() : present()
    }

    // MARK: - The big bar

    @objc private func present() {
        Log.write("present() called, active=\(NSApp.isActive)")
        canvasView.hideControls()
        wantsBar = true
        presentBar(attempt: 0)
    }

    /// Presenting can silently not stick: the row may be a few points too wide
    /// for the bar to lay out, or something else (a menu opening, the app
    /// activating) can take the Touch Bar back right after we ask for it. In
    /// both cases the canvas ends up with no window or draws zero frames, so
    /// verify shortly after and try again rather than trusting the call.
    private func presentBar(attempt: Int) {
        if let existing = modalBar {
            NSTouchBar.dismissSystemModalTouchBar(existing)
            modalBar = nil
        }
        let bar = NSTouchBar()
        bar.delegate = self
        // Full screen drops the buttons so the scene spans the whole bar.
        // Exit via the Control Strip icon or the menu bar item.
        bar.defaultItemIdentifiers = fullScreen
            ? [.canvas]
            : [.close, .prev, .next, .canvas]
        modalBar = bar
        NSTouchBar.presentSystemModalTouchBar(bar, placement: 1, systemTrayItemIdentifier: .strip)
        isPresented = true
        canvasView.resetFrameCount()
        canvasView.start()
        Log.write("  presented attempt=\(attempt) full=\(fullScreen) width=\(canvasWidthConstraint?.constant ?? -1)")

        guard attempt < 5 else { Log.write("  gave up after \(attempt) attempts"); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + 0.4 * Double(attempt)) { [weak self] in
            guard let self, self.wantsBar else { return }
            let attached = self.canvasView.window != nil
            let frames = self.canvasView.framesDrawn
            Log.write("  check attempt=\(attempt) window=\(attached) frames=\(frames) size=\(self.canvasView.bounds.size)")

            // Two distinct failures, distinguishable and needing different fixes:
            //   no window            -> the bar was never laid out, or something
            //                           took it back. Just ask again.
            //   window but 0 frames  -> the item row is too wide to lay out.
            //                           Retrying alone will never help; shrink.
            if attached && frames > 0 { return }
            if attached && frames == 0 {
                self.activeWidth -= 40
                Log.write("  too wide, shrinking to \(self.activeWidth)")
            }
            self.presentBar(attempt: attempt + 1)
        }
    }

    private func dismiss() {
        Log.write("dismiss() isPresented=\(isPresented)")
        wantsBar = false
        if let bar = modalBar {
            NSTouchBar.dismissSystemModalTouchBar(bar)
        }
        modalBar = nil
        isPresented = false
        canvasView?.stop()
    }

    func touchBar(_ touchBar: NSTouchBar,
                  makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case .canvas:
            let item = NSCustomTouchBarItem(identifier: identifier)
            // The bar sizes custom views from their constraints, so an explicit
            // width is required. Leaving it flexible collapses the view to 0pt.
            if canvasWidthConstraint == nil {
                let c = canvasView.widthAnchor.constraint(equalToConstant: activeWidth)
                c.priority = .required
                c.isActive = true
                canvasWidthConstraint = c
                canvasView.heightAnchor.constraint(equalToConstant: 30).isActive = true
            }
            canvasWidthConstraint?.constant = activeWidth
            item.view = canvasView
            return item

        case .close:
            return button(identifier, kind: .close) { [weak self] in self?.closeTapped() }
        case .prev:
            return button(identifier, kind: .prev) { [weak self] in self?.prevTapped() }
        case .next:
            return button(identifier, kind: .next) { [weak self] in self?.nextTapped() }
        default:
            return nil
        }
    }

    private func button(_ id: NSTouchBarItem.Identifier, kind: BarButtonView.Kind,
                        _ onTap: @escaping () -> Void) -> NSCustomTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: id)
        let b = BarButtonView(kind: kind, width: 52)
        b.onTap = onTap
        item.view = b
        return item
    }

    @objc private func closeTapped() { dismiss() }
    @objc private func nextTapped() { select((index + 1) % toys.count) }
    @objc private func prevTapped() { select((index - 1 + toys.count) % toys.count) }

    private func select(_ i: Int) {
        index = i
        defaults.set(toy.title, forKey: toyKey)
        canvasView.toy = toy
        rebuildMenu()
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🌈"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        rebuildMenu()
    }

    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        Log.write("statusClicked type=\(String(describing: event?.type)) active=\(NSApp.isActive)")
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            stripTapped()
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let groups = Toys.groups()
        var labels = ["Show on Touch Bar", "Keep Icon in Control Strip",
                      "Full Screen", "Double-Tap for Controls", "Edit Marquee Text…",
                      "Launch at Login", "Quit"]
        labels += groups.flatMap { g in g.toys.map { "\($0.emoji)  \($0.title)" } }
        let w = MenuRowView.width(for: labels)

        var flat = 0
        for group in groups {
            row(menu, group.name.uppercased(), width: w, header: true)
            for toy in group.toys {
                let item = row(menu, "\(toy.emoji)  \(toy.title)", width: w,
                               action: #selector(pickToy(_:)))
                item.tag = flat
                item.state = (flat == index) ? .on : .off
                flat += 1
            }
            menu.addItem(.separator())
        }

        row(menu, "Show on Touch Bar", width: w, action: #selector(present))
        let strip = row(menu, "Keep Icon in Control Strip", width: w, action: #selector(toggleStrip))
        strip.state = defaults.bool(forKey: stripKey) ? .on : .off
        let full = row(menu, "Full Screen", width: w, action: #selector(toggleFullScreen))
        full.state = fullScreen ? .on : .off
        let dbl = row(menu, "Double-Tap for Controls", width: w, action: #selector(toggleDoubleTap))
        dbl.state = defaults.bool(forKey: doubleTapKey) ? .on : .off
        row(menu, "Edit Marquee Text…", width: w, action: #selector(editMarqueeText))
        let login = row(menu, "Launch at Login", width: w, action: #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(.separator())
        row(menu, "Quit", width: w, action: #selector(quit))

        self.menu = menu
    }

    @discardableResult
    private func row(_ menu: NSMenu, _ label: String, width: CGFloat,
                     action: Selector? = nil, header: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: label, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = !header && action != nil
        item.view = MenuRowView(label: label, width: width, isHeader: header)
        menu.addItem(item)
        return item
    }

    @objc private func pickToy(_ sender: NSMenuItem) {
        select(sender.tag)
        if !isPresented { present() }
    }

    @objc private func toggleStrip() {
        let on = !defaults.bool(forKey: stripKey)
        defaults.set(on, forKey: stripKey)
        DFR.setControlStripPresence(.strip, on)
        ControlStrip.setPinned(NSTouchBarItem.Identifier.strip.rawValue, on)
        rebuildMenu()
    }

    @objc private func toggleFullScreen() {
        defaults.set(!fullScreen, forKey: fullScreenKey)
        rebuildMenu()
        if isPresented { present() }        // rebuild the bar in the new mode
    }

    @objc private func toggleDoubleTap() {
        let on = !defaults.bool(forKey: doubleTapKey)
        defaults.set(on, forKey: doubleTapKey)
        canvasView.doubleTapEnabled = on
        if !on { canvasView.hideControls() }
        rebuildMenu()
    }

    /// Opens the marquee's text file in whatever edits .txt. A file rather than
    /// an in-app field because AppKit text controls don't render in this app.
    @objc private func editMarqueeText() {
        NSWorkspace.shared.open(MarqueeToy.ensureTextFile())
    }

    @objc private func toggleLogin() {
        LoginItem.set(!LoginItem.isEnabled)
        rebuildMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
