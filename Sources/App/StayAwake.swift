import Foundation
import IOKit.pwr_mgt

/// Keeps the Touch Bar lit while a scene is on it.
///
/// The assertion is taken when a scene is presented and dropped the moment it
/// is dismissed, so it never applies to the ordinary Touch Bar. Note that
/// `PreventUserIdleDisplaySleep` is the same idle timer that dims the main
/// screen, so while it is held the screen stays on too. macOS powers the Touch
/// Bar down with the display, so there is no assertion that keeps one awake
/// without the other.
enum StayAwake {
    private static var assertion: IOPMAssertionID = IOPMAssertionID(0)
    private(set) static var isHeld = false

    static func begin(reason: String = "Touch Bar Toys scene is on the bar") {
        guard !isHeld else { return }
        var id = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id)
        guard status == kIOReturnSuccess else {
            Log.write("stay-awake: assertion failed with \(status)")
            return
        }
        assertion = id
        isHeld = true
        Log.write("stay-awake: assertion taken")
    }

    static func end() {
        guard isHeld else { return }
        IOPMAssertionRelease(assertion)
        isHeld = false
        Log.write("stay-awake: assertion released")
    }
}
