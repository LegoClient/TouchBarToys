import Foundation

/// Registering an item with DFR makes it *available* to the Control Strip, but
/// once the user has customised their strip the Touch Bar renders exactly the
/// stored identifier list and nothing else. A third-party item therefore has to
/// be inserted into that list to actually appear.
enum ControlStrip {
    private static let domain = "com.apple.controlstrip" as CFString
    /// `FullCustomized` is the expanded strip, `MiniCustomized` the collapsed one.
    private static let keys = ["FullCustomized", "MiniCustomized"]

    /// True when the user has a customised strip at all. If they don't, the
    /// system falls back to its defaults and DFR presence alone is enough.
    static var isCustomised: Bool {
        keys.contains { CFPreferencesCopyAppValue($0 as CFString, domain) as? [String] != nil }
    }

    static func contains(_ id: String) -> Bool {
        keys.contains {
            (CFPreferencesCopyAppValue($0 as CFString, domain) as? [String])?.contains(id) ?? false
        }
    }

    @discardableResult
    static func setPinned(_ id: String, _ pinned: Bool) -> Bool {
        var changed = false
        for key in keys {
            guard var list = CFPreferencesCopyAppValue(key as CFString, domain) as? [String]
            else { continue }
            let has = list.contains(id)
            if pinned && !has {
                list.append(id)
            } else if !pinned && has {
                list.removeAll { $0 == id }
            } else {
                continue
            }
            CFPreferencesSetAppValue(key as CFString, list as CFArray, domain)
            changed = true
        }
        if changed {
            CFPreferencesAppSynchronize(domain)
            // ControlStrip caches the layout; it relaunches itself immediately.
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            p.arguments = ["ControlStrip"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
        return changed
    }
}
