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
    }

    /// `divider` returns the divider's current top-left-origin frame; it shifts as icons cross it.
    static func arrange(hidden: Set<String>, divider: () -> CGRect?) async -> Outcome {
        var outcome = Outcome()
        guard MenuDiscovery.trusted else { outcome.failed = Array(hidden); return outcome }
        let items = await Task.detached(priority: .userInitiated) { MenuDiscovery.scan().items }.value
            .filter { $0.kind == .menu && MenuBarSections.movable($0.id) && $0.element != nil }
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        outcome.missing = hidden.filter { byID[$0] == nil }.sorted()
        guard let start = divider() else { outcome.failed = Array(hidden); return outcome }
        let placements = items.compactMap { item -> MenuBarSections.Placement? in
            guard let frame = item.element.flatMap(MenuDiscovery.frame), sameBar(frame, start) else { return nil }
            return MenuBarSections.Placement(id: item.id, midX: frame.midX)
        }
        let pointer = CGEvent(source: nil)?.location
        defer { if let pointer { CGWarpMouseCursorPosition(pointer) } }
        for move in MenuBarSections.moves(items: placements, dividerMidX: start.midX, hidden: hidden) {
            guard let element = byID[move.id]?.element, let from = MenuDiscovery.frame(element),
                  let target = divider() else { outcome.failed.append(move.id); continue }
            await commandDrag(from: CGPoint(x: from.midX, y: from.midY),
                              to: MenuBarSections.dropPoint(divider: target, toHidden: move.toHidden))
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let after = MenuDiscovery.frame(element), let line = divider() else { outcome.failed.append(move.id); continue }
            if (after.midX < line.midX) == move.toHidden { outcome.moved += 1 } else { outcome.failed.append(move.id) }
        }
        return outcome
    }

    /// Menu bars repeat on every display; only icons in the divider's own bar can cross it.
    private static func sameBar(_ item: CGRect, _ divider: CGRect) -> Bool {
        abs(item.midY - divider.midY) < 12 && NSScreen.screens.contains { screen in
            let bounds = MenuBarSections.flipped(screen.frame, primaryHeight: primaryHeight)
            return bounds.contains(CGPoint(x: divider.midX, y: divider.midY)) && bounds.minX <= item.midX && item.midX <= bounds.maxX
        }
    }

    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private static func commandDrag(from: CGPoint, to: CGPoint) async {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        func post(_ type: CGEventType, _ point: CGPoint) {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
        post(.mouseMoved, from)
        try? await Task.sleep(nanoseconds: 40_000_000)
        post(.leftMouseDown, from)
        // The menu bar only starts a drag after a short hold.
        try? await Task.sleep(nanoseconds: 120_000_000)
        let steps = 14
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
            try? await Task.sleep(nanoseconds: 12_000_000)
        }
        try? await Task.sleep(nanoseconds: 60_000_000)
        post(.leftMouseUp, to)
    }
}
