import AppKit
import ApplicationServices

/// Moves menu extras across Loki's divider with the same Command-drag a person would make.
/// Public APIs only: Accessibility for positions, CGEvent for the drag. Every move is re-read
/// afterwards, so a failure is reported instead of assumed away.
@MainActor
enum MenuBarArranger {
    struct Outcome {
        var moved = 0
        var failed: [String] = []
        var missing: [String] = []
        /// Display names for `failed`, so the message can say which icons stayed put.
        var failedTitles: [String] = []
    }

    /// `divider` returns the divider's current top-left-origin frame; it shifts as icons cross it.
    /// `collapse(true)` widens the divider, `collapse(false)` shrinks it back to its drop-target width.
    ///
    /// Sides are read only while collapsed: there, hidden icons sit off-screen left of the divider.
    /// While revealed on a notched display, macOS draws icons near the notch out of their real order,
    /// so revealed positions can only aim a drag, never confirm one (measured on macOS 26.5).
    static func arrange(hidden: Set<String>, divider: () -> CGRect?, collapse: (Bool) -> Void) async -> Outcome {
        var outcome = Outcome()
        guard MenuDiscovery.trusted else { outcome.failed = Array(hidden); return outcome }
        let items = await Task.detached(priority: .userInitiated) { MenuDiscovery.scan().items }.value
            .filter { $0.kind == .menu && MenuBarSections.movable($0.id) && $0.element != nil }
        guard !Task.isCancelled else { return outcome }
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        outcome.missing = hidden.filter { byID[$0] == nil }.sorted()

        func pending() async -> [MenuBarSections.Move]? {
            guard !Task.isCancelled else { return nil }
            collapse(true)
            try? await Task.sleep(nanoseconds: settle)
            guard let line = divider() else { return nil }
            let placements = items.compactMap { item -> MenuBarSections.Placement? in
                guard let frame = item.element.flatMap(MenuDiscovery.frame), collapsedBar(frame, line) else { return nil }
                return MenuBarSections.Placement(id: item.id, midX: frame.midX)
            }
            return MenuBarSections.moves(items: placements, dividerMidX: line.midX, hidden: hidden)
        }

        guard let planned = await pending() else { outcome.failed = Array(hidden); return outcome }
        var remaining = planned
        let pointer = CGEvent(source: nil)?.location
        defer { if let pointer { CGWarpMouseCursorPosition(pointer) } }
        for attempt in 0..<2 where !remaining.isEmpty {
            collapse(false)
            try? await Task.sleep(nanoseconds: settle)
            for move in remaining {
                guard !Task.isCancelled else { return outcome }
                guard let item = byID[move.id], let element = item.element, let from = MenuDiscovery.frame(element),
                      let target = divider() else { continue }
                await commandDrag(from: CGPoint(x: from.midX, y: from.midY),
                                  to: MenuBarSections.dropPoint(divider: target, toHidden: move.toHidden, attempt: attempt),
                                  window: statusWindow(for: from, owner: item.pid))
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            guard let next = await pending() else { break }
            remaining = next
        }
        let left = Set(remaining.map(\.id))
        outcome.moved = planned.filter { !left.contains($0.id) }.count
        outcome.failed = remaining.map(\.id)
        outcome.failedTitles = remaining.map { byID[$0.id]?.title ?? $0.id }
        return outcome
    }

    /// Read only while collapsed; revealed positions near a notch cannot establish which side owns an icon.
    static func hasUnexpectedHiddenItems(hidden: Set<String>, divider: () -> CGRect?) async -> Bool {
        let placements = await Task.detached(priority: .utility) {
            MenuDiscovery.scan().items.compactMap { item -> (String, CGRect)? in
                guard item.kind == .menu, MenuBarSections.movable(item.id),
                      let frame = item.element.flatMap(MenuDiscovery.frame) else { return nil }
                return (item.id, frame)
            }
        }.value
        guard !Task.isCancelled, let line = divider() else { return false }
        let items = placements.filter { collapsedBar($0.1, line) }
            .map { MenuBarSections.Placement(id: $0.0, midX: $0.1.midX) }
        return MenuBarSections.moves(items: items, dividerMidX: line.midX, hidden: hidden).contains { !$0.toHidden }
    }

    private static let settle: UInt64 = 400_000_000

    /// The display whose menu bar holds the divider's visible right end.
    private static func collapsedBar(_ item: CGRect, _ divider: CGRect) -> Bool {
        let edge = CGPoint(x: divider.maxX - 1, y: divider.midY)
        return NSScreen.screens.contains { screen in
            let bounds = MenuBarSections.flipped(screen.frame, primaryHeight: primaryHeight)
            return bounds.contains(edge) && MenuBarSections.onCollapsedBar(item, divider: divider, display: bounds)
        }
    }

    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func statusWindow(for frame: CGRect, owner: pid_t) -> MenuGeometry.StatusWindow? {
        let hosts = Set(NSWorkspace.shared.runningApplications.filter {
            ["com.apple.controlcenter", "com.apple.MenuBarAgent"].contains($0.bundleIdentifier ?? "")
        }.map(\.processIdentifier))
        let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = list.compactMap { info -> MenuGeometry.StatusWindow? in
            guard info[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.statusWindow)),
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rectangle = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return .init(id: id, pid: pid, frame: rectangle)
        }
        return MenuGeometry.statusWindow(for: frame, owner: owner, hosts: hosts, windows: windows)
    }

    static func commandDrag(from: CGPoint, to: CGPoint, window: MenuGeometry.StatusWindow?) async {
        let visibleSource = NSScreen.screens.contains { screen in
            let area = screen.auxiliaryTopRightArea ?? CGRect(x: screen.frame.minX + 120,
                y: screen.frame.maxY - NSStatusBar.system.thickness,
                width: max(0, screen.frame.width - 120), height: NSStatusBar.system.thickness)
            return MenuBarSections.flipped(area, primaryHeight: primaryHeight).contains(from)
        }
        guard window != nil || visibleSource,
              let source = CGEventSource(stateID: .hidSystemState) else { return }
        func post(_ type: CGEventType, _ point: CGPoint) {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
            event.flags = .maskCommand
            if let window {
                // Coordinate-only input cannot identify an item whose slot lies beneath the notch.
                event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(window.pid))
                event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.id))
                event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window.id))
                event.post(tap: .cgAnnotatedSessionEventTap)
            } else {
                event.post(tap: .cghidEventTap)
            }
        }
        if window == nil {
            post(.mouseMoved, from)
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        guard !Task.isCancelled else { return }
        post(.leftMouseDown, from)
        defer { post(.leftMouseUp, to) }
        // The menu bar only starts a drag after a short hold.
        try? await Task.sleep(nanoseconds: 120_000_000)
        let steps = 14
        for step in 1...steps {
            guard !Task.isCancelled else { return }
            let t = CGFloat(step) / CGFloat(steps)
            post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
            try? await Task.sleep(nanoseconds: 12_000_000)
        }
        try? await Task.sleep(nanoseconds: 60_000_000)
    }
}
