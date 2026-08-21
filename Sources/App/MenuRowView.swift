import AppKit

/// Menu rows we draw ourselves.
///
/// On macOS 26 this app's status-menu item titles render as nothing. The rows,
/// separators and checkmarks appear but the text never does, while fonts,
/// colours and titles all check out at runtime. Owning the drawing sidesteps
/// whatever the system is doing with the title text.
final class MenuRowView: NSView {
    private let label: String
    private let isHeader: Bool
    private var tracking: NSTrackingArea?
    /// Used when rendering the rows offscreen, where there is no menu item.
    var forcedState: NSControl.StateValue?

    init(label: String, width: CGFloat, isHeader: Bool = false) {
        self.label = label
        self.isHeader = isHeader
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: isHeader ? 18 : 20))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    static let leading: CGFloat = 24
    static let trailing: CGFloat = 18

    static func font() -> NSFont { .menuFont(ofSize: 0) }

    static func width(for labels: [String]) -> CGFloat {
        let f = font()
        let widest = labels.map {
            NSAttributedString(string: $0, attributes: [.font: f]).size().width
        }.max() ?? 120
        return ceil(widest) + leading + trailing
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .mouseMoved],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { needsDisplay = true }
    override func mouseExited(with event: NSEvent) { needsDisplay = true }
    override func mouseMoved(with event: NSEvent) { needsDisplay = true }

    override func mouseUp(with event: NSEvent) {
        performAction()
    }

    /// Split out from mouseUp so the menu -> action path can be exercised in tests.
    func performAction() {
        Log.write("row click '\(label)' item=\(enclosingMenuItem != nil) enabled=\(enclosingMenuItem?.isEnabled ?? false) header=\(isHeader)")
        guard let item = enclosingMenuItem, item.isEnabled, !isHeader else {
            Log.write("  -> ignored")
            return
        }
        item.menu?.cancelTracking()
        guard let action = item.action else { return }
        // Defer until the menu has actually gone away. Presenting a
        // system-modal Touch Bar while tracking is unwinding does nothing.
        // Let the menu fully close first. While it is open the Touch Bar is
        // showing the menu's own context, and anything we present is discarded
        // when that context is restored.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let ok = NSApp.sendAction(action, to: item.target, from: item)
            Log.write("  -> sendAction \(NSStringFromSelector(action)) target=\(item.target != nil) returned \(ok)")
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let item = enclosingMenuItem
        let enabled = (item?.isEnabled ?? true) && !isHeader
        let highlighted = (item?.isHighlighted ?? false) && enabled

        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1),
                         xRadius: 5, yRadius: 5).fill()
        }

        let color: NSColor = isHeader ? .secondaryLabelColor
            : highlighted ? .selectedMenuItemTextColor
            : enabled ? .labelColor : .disabledControlTextColor

        if (item?.state ?? forcedState ?? .off) == .on {
            let check = NSAttributedString(string: "✓", attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: color,
            ])
            check.draw(at: NSPoint(x: 9, y: (bounds.height - check.size().height) / 2))
        }

        let text = NSAttributedString(string: label, attributes: [
            .font: MenuRowView.font(), .foregroundColor: color,
        ])
        text.draw(at: NSPoint(x: MenuRowView.leading,
                              y: (bounds.height - text.size().height) / 2))
    }
}
