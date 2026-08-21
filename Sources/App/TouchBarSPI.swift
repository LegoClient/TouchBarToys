import AppKit
import Foundation

/// DFRFoundation lives only in the dyld shared cache — there is no .tbd to link
/// against, so its C functions are resolved with dlsym at first use.
enum DFR {
    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard let handle else { return nil }
        return dlsym(handle, name)
    }

    static var isAvailable: Bool { handle != nil }

    /// Pin (or unpin) a Touch Bar item in the Control Strip on the right.
    static func setControlStripPresence(_ id: NSTouchBarItem.Identifier, _ present: Bool) {
        guard let s = symbol("DFRElementSetControlStripPresenceForIdentifier") else { return }
        typealias Fn = @convention(c) (NSString, ObjCBool) -> Void
        unsafeBitCast(s, to: Fn.self)(id.rawValue as NSString, ObjCBool(present))
    }

    static func showsCloseBoxWhenFrontMost(_ show: Bool) {
        guard let s = symbol("DFRSystemModalShowsCloseBoxWhenFrontMost") else { return }
        typealias Fn = @convention(c) (ObjCBool) -> Void
        unsafeBitCast(s, to: Fn.self)(ObjCBool(show))
    }
}

enum TouchBarSPI {
    /// Every private entry point we rely on, checked up front so a future macOS
    /// that drops one produces a clear message instead of a crash.
    static var missing: [String] {
        var gone: [String] = []
        let itemCls: AnyClass = NSTouchBarItem.self
        let barCls: AnyClass = NSTouchBar.self
        if !itemCls.responds(to: #selector(NSTouchBarItem.addSystemTrayItem(_:))) {
            gone.append("+[NSTouchBarItem addSystemTrayItem:]")
        }
        if !barCls.responds(to: #selector(NSTouchBar.presentSystemModalTouchBar(_:placement:systemTrayItemIdentifier:))) {
            gone.append("+[NSTouchBar presentSystemModalTouchBar:placement:systemTrayItemIdentifier:]")
        }
        if !DFR.isAvailable { gone.append("DFRFoundation.framework") }
        return gone
    }
}
