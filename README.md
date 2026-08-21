# Touch Bar Toys

[![build](https://github.com/LegoClient/TouchBarToys/actions/workflows/build.yml/badge.svg)](https://github.com/LegoClient/TouchBarToys/actions/workflows/build.yml)

Thirty-two pointless, flashy things for the MacBook Pro Touch Bar: screensavers,
demoscene effects, small games, and a few system monitors that are actually
useful.

Native Swift, no dependencies, builds with Command Line Tools. Xcode not needed.

![Classics](docs/sheet-classics.png)
![Made for the strip](docs/sheet-made-for-the-strip.png)

## Requirements

* A Mac with a Touch Bar. Developed on an Intel MacBook Pro 16", macOS 26.1.
* Xcode Command Line Tools (`xcode-select --install`).

CI builds it on Apple Silicon too (macOS 26.5, Swift 6.3, arm64), so the source
is architecture-clean. That's academic, since Touch Bar hardware only ever
shipped on Intel MacBook Pros.

## Install

Grab the latest build from [Releases][releases], unzip it, drag it to
`/Applications`. It's x86_64, because every Mac with a Touch Bar is an Intel Mac.

The first launch will be blocked, because the app is ad-hoc signed rather than
notarized. Open it once and let macOS refuse, then go to System Settings >
Privacy & Security, scroll down, and click Open Anyway. You only do this once.

Or build it yourself. Takes about ten seconds, and there's no Gatekeeper prompt
at all, since locally built apps never get quarantined:

```bash
git clone https://github.com/LegoClient/TouchBarToys.git
cd TouchBarToys && ./build.sh && cp -R build/TouchBarToys.app /Applications/
open /Applications/TouchBarToys.app
```

It's a menu-bar accessory, so there's no Dock icon and no window. The build
ad-hoc signs it for you.

[releases]: https://github.com/LegoClient/TouchBarToys/releases/latest

### Cutting a release

Build the artifact on an Intel Mac, or cross-compile. CI runners are arm64, and
an arm64 build is no use on Touch Bar hardware.

```bash
./build.sh
ditto -c -k --sequesterRsrc --keepParent build/TouchBarToys.app TouchBarToys.zip
gh release upload vX.Y.Z TouchBarToys.zip
```

Use `ditto` rather than `zip`, so the code signature survives the round trip.

## Use

There's a rainbow in your menu bar, and a small rainbow icon in the Control
Strip at the right of the Touch Bar.

| | |
|---|---|
| Left-click the menu bar icon | open or close the scene on the Touch Bar |
| Right-click the menu bar icon | menu: pick a scene, toggles, quit |
| Tap the Control Strip icon | same as left-clicking the menu bar icon |
| `◀` `▶` on the bar | previous / next scene |
| `✕` on the bar | close |

Menu options:

* **Full Screen.** Drops the three buttons so the scene spans the whole bar,
  1050pt instead of 812pt. Taps then go to the scene itself, so you exit with
  the Control Strip icon or the menu bar icon, and switch scenes from the menu.
* **Keep Icon in Control Strip.** Pins or unpins the Touch Bar icon. See
  [the Control Strip note](#the-control-strip-needs-more-than-the-api-suggests)
  for what this actually changes on your system.
* **Edit Marquee Text…** Opens
  `~/Library/Application Support/TouchBarToys/marquee.txt`. One message per
  line, and tapping the bar cycles through them. It's re-read every 2 seconds,
  so edits show up live. The 3x5 font covers A-Z, 0-9 and a little punctuation;
  anything else turns into a space.
* **Launch at Login.** Installs a user LaunchAgent. Not `SMAppService`, which
  wants a Developer ID signature.

Animation only runs while the bar is open, so it costs nothing when idle.

## The scenes

**Classics.** Rainbow Pop-Tart Cat, DVD Bounce (it counts real corner hits),
Matrix Rain, Doom Fire†, Hyperspace†

**Made for the Strip.** Rule 110† (elementary cellular automata), Game of Life†,
Pendulum Wave†, Tunnels†, LED Marquee†

**Touch.** Falling Sand† (sand, water, stone), Ripples†, Fireworks†, Lightning†

**Games.** Flap†, Dino Runner†, Pong (plays itself), Reaction Timer†

**Ambient.** Plasma†, Metaballs†, Aquarium†, Snowfall†, Aurora†, Mandelbrot†

**System.** CPU Spectrum, Battery, Network, Memory & Disk, Clock†

**Silly.** Hacker Terminal†, Almost Done†, Dominoes†

(† responds to touch.)

<details>
<summary>More screenshots</summary>

![Touch](docs/sheet-touch.png)
![Games](docs/sheet-games.png)
![Ambient](docs/sheet-ambient.png)
![System](docs/sheet-system.png)
![Silly](docs/sheet-silly.png)

</details>

## Adding a scene

One class conforming to `Toy`, plus a line in the registry in
`Sources/Toys/Toy.swift`.

```swift
final class MyToy: PixelToy {
    override var title: String { "My Toy" }
    override var emoji: String { "🎃" }
    override var pixelHeight: Int { 30 }   // virtual canvas height

    override func update(dt: Double, size: CGSize) { /* advance state */ }
    override func renderPixels(into buf: PixelBuffer) { /* plot chunky pixels */ }
    override func tap(at p: CGPoint, size: CGSize) { /* optional */ }
}
```

`PixelToy` hands you a low-resolution `PixelBuffer` that gets scaled up with
nearest-neighbour, which is what makes everything look like a 1998 screensaver.
If you'd rather draw into the real `CGContext` at full resolution, conform to
`Toy` directly; `DVDToy`, `ClockToy` and the system monitors all do that.
`MicroFont` is a 3x5 pixel font for scores and labels, and `Text` draws crisp
CoreText for anything bigger.

## Development

You can't screenshot the Touch Bar from a script. It isn't a CoreGraphics
display, and the Cmd+Shift+6 shortcut needs Accessibility permission. So there's
an offscreen renderer that draws every scene at Touch Bar geometry. All the
pixel art was tuned through it, without a Touch Bar in the loop.

```bash
swiftc -O -o build/render Sources/Toys/*.swift Sources/Render/main.swift
./build/render preview      # per-group contact sheets, plus a PNG of every scene
./build/render x --bench    # per-frame cost of every scene
```

At 30fps the heaviest scene (Mandelbrot) is about 10% of one core, and most are
under 1%. Anything above 10% in `--bench` is worth a look.

The app has several diagnostic modes, which exist because most of the bugs in
this project were invisible:

```bash
./build/TouchBarToys.app/Contents/MacOS/TouchBarToys --selftest
```

| mode | what it does |
|---|---|
| `--selftest` | drives the whole Touch Bar path headlessly, reports whether the canvas made it onto the bar |
| `--testbuttons` | presents the bar, fires the real button handlers, checks they changed something |
| `--testmenu` | opens the menu and fires a row's action through the real code path |
| `--diag` | menu model, resolved colours, Control Strip registration |
| `--menumock` | renders the menu rows offscreen to `/tmp/tbt-menu-mock.png` |
| `--fontprobe` | glyph lookup, plus rasterised ink counts |
| `--menushot` | captures live windows (unreliable for text, see below) |

Every launch also writes a trace to `~/Library/Logs/TouchBarToys.log`.

## How it works

macOS has no public API for putting your own content on the Touch Bar outside
your own app's window. Three private entry points do it, and all three still
exist on macOS 26.1:

* `+[NSTouchBarItem addSystemTrayItem:]` registers an item with the system tray.
* `DFRElementSetControlStripPresenceForIdentifier()` pins it into the Control
  Strip.
* `+[NSTouchBar presentSystemModalTouchBar:placement:systemTrayItemIdentifier:]`
  takes over the whole bar with `placement: 1`.

The Objective-C methods are declared as categories in `Sources/App/PrivateAPI.h`.
A declaration is enough, because ObjC dispatch needs no link-time symbol.
`DFRFoundation` has no linkable stub, since it exists only in the dyld shared
cache, so its C functions get resolved with `dlsym`. `TouchBarSPI.missing` checks
all three at launch and shows a plain error instead of crashing, in case a
future macOS drops one.

## Field notes

Most of the work here went into things that fail silently. Writing them down in
case they save someone else an afternoon.

### Anything AppKit draws for you might not appear

In this app, `NSMenuItem` titles render as nothing at all on macOS 26. Rows,
separators and checkmarks draw fine; the text never does. Everything checks out
at runtime: all titles present, `labelColor` white at 0.85 alpha, `.SFNS-Regular`
resolving glyphs, and text rasterising to 410 ink pixels in an offscreen bitmap
through every drawing path. Setting `NSApp.mainMenu`, which a nib-less app
doesn't have, made no difference.

It isn't limited to text, or to menus. `NSButton` renders nothing whatsoever:
not a title, not a symbol image, not even its bezel. The `✕` `◀` `▶` items and
the Control Strip icon all came out as empty slots.

The rule that holds up: anything you draw yourself in an `NSView` renders, and
stock controls might not. `MenuRowView` and `BarButtonView` draw their own
labels, checkmarks, glyphs and highlights with Bezier paths, and all of it
appears.

### Drawing it yourself costs you the events too

A custom `NSView` in the Touch Bar receives no touches at all until it sets
`allowedTouchTypes = [.direct]`, and taps then arrive as `touchesBegan` and
`touchesEnded`, not `mouseDown` and `mouseUp`. `NSControl` does this internally,
so it's easy to miss. The hand-drawn buttons looked perfect and were completely
inert.

### cacheDisplay on a menu window drops text

Rendering a live menu window with `cacheDisplay(in:to:)` captures emoji, which
are image glyphs, and no text whatsoever. It looks exactly like a font bug that
isn't there. Use `--menumock` to check row drawing offscreen instead.

### NSTouchBar layout fails silently in two different directions

`NSTouchBar` sizes custom views from their constraints. A flexible width
collapses the canvas to 0pt. A width that makes the item row even slightly too
wide makes the bar quietly decline to lay it out, so the view gets a window but
never draws a frame. On this machine the ceiling was about 950pt beside two
stock buttons, about 880pt beside the drawn ones, and about 812pt once `◀` was
added, which is the default.

Full-screen mode can't be calibrated the same way. With a single item the bar
clips an oversize canvas instead of refusing it, so a 1400pt canvas still
reports a healthy 30fps while running off the edge, and the zero-frames check is
blind to it. The 1050pt figure comes from the button-mode measurements instead:
a total item row of about 1070pt laid out, and about 1080pt did not.
`TBT_CANVAS_WIDTH` and `TBT_FULL_WIDTH` override both for tuning.

### Presenting the bar is not reliable

While a menu is open, the Touch Bar shows that menu's own context, and anything
presented during it gets discarded when the context is restored. That's why
"Show on Touch Bar" did nothing at all. So `presentBar(attempt:)` treats
presentation as unreliable: it checks 0.8s later whether the canvas actually drew
a frame, and retries if not. It only shrinks the width once a straight retry has
already failed, since a too-wide row won't fix itself on a retry but a stolen bar
will. Menu rows also wait 0.3s after `cancelTracking()` before firing their
action.

### The Control Strip needs more than the API suggests

`DFRElementSetControlStripPresenceForIdentifier` makes an item available, but
that's not the same as visible. Once you've customised your Control Strip, the
Touch Bar renders exactly the identifier list stored in `com.apple.controlstrip`
(`FullCustomized` for the expanded strip, `MiniCustomized` for the collapsed
one) and ignores anything not in it. "Keep Icon in Control Strip" inserts and
removes the identifier there, then restarts `ControlStrip` to reload the layout.

## Uninstall

```bash
# quit, remove the app and the login item
pkill -f TouchBarToys
rm -rf /Applications/TouchBarToys.app
launchctl bootout gui/$UID/com.touchbartoys.app 2>/dev/null
rm -f ~/Library/LaunchAgents/com.touchbartoys.app.plist
```

Then unpin the Control Strip icon. Check whether it's listed:

```bash
defaults read com.apple.controlstrip FullCustomized
```

If `com.touchbartoys.app.strip` is in there, remove it from `FullCustomized` and
`MiniCustomized`, then run `killall ControlStrip`. Toggling Keep Icon in Control
Strip off before you uninstall does all of that for you.

## Caveats

This app depends on private API, so a macOS update could break it without
warning. If that happens you get a plain "can't run on this macOS" dialog naming
the missing symbol, and `--selftest` will tell you which part gave out. It's
ad-hoc signed, so it won't pass notarisation.

## License

MIT, see [LICENSE](LICENSE).
