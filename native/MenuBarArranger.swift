import AppKit
import ApplicationServices

/// Delivers drags to status windows, including icons outside the visible menu bar.
/// Accessibility positions after collapse, not event delivery, determine success.
@MainActor
enum MenuBarArranger {
    struct Outcome {
        var moved = 0
        var failed: [String] = []
        var missing: [String] = []
        var diagnostics: [String] = []
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
        for attempt in 0..<2 where !remaining.isEmpty {
            collapse(false)
            try? await Task.sleep(nanoseconds: settle)
            for move in remaining {
                guard !Task.isCancelled else { return outcome }
                guard let item = byID[move.id], let element = item.element, let from = MenuDiscovery.frame(element),
                      let target = divider() else { continue }
                let sourceWindow = statusWindow(for: from, owner: item.pid)
                let targetWindow = statusWindow(for: target, owner: ProcessInfo.processInfo.processIdentifier)
                let sent = await commandDrag(from: CGPoint(x: from.midX, y: from.midY),
                                             to: MenuBarSections.dropPoint(divider: target, toHidden: move.toHidden, attempt: attempt),
                                             window: sourceWindow, destination: targetWindow, receiver: item.pid)
                outcome.diagnostics.append("attempt=\(attempt + 1) item=\(move.id) from=\(from) divider=\(target) receiver=\(item.pid) sourceWindow=\(String(describing: sourceWindow)) targetWindow=\(String(describing: targetWindow)) dispatched=\(sent)")
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            guard let next = await pending() else { break }
            outcome.diagnostics.append("remaining=\(next.map(\.id).joined(separator: ","))")
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

    // The public hit-test hints do not set NSEvent.windowNumber; field 0x33 does.
    static let eventWindowNumber = CGEventField(rawValue: 0x33)!

    static func dragEvent(_ type: CGEventType, at point: CGPoint,
                          target: MenuGeometry.StatusWindow, receiver: pid_t,
                          source: CGEventSource) -> CGEvent? {
        guard target.id != 0, receiver > 0, point.x.isFinite, point.y.isFinite,
              let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left) else { return nil }
        event.flags = type == .leftMouseDown ? .maskCommand : []
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(receiver))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(target.id))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(target.id))
        event.setIntegerValueField(eventWindowNumber, value: Int64(target.id))
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        return event
    }

    @discardableResult
    static func commandDrag(from: CGPoint, to: CGPoint, window: MenuGeometry.StatusWindow?,
                            destination: MenuGeometry.StatusWindow?, receiver: pid_t,
                            deliver: @escaping (CGEvent, pid_t) async throws -> Void = { event, pid in
                                try await MenuBarEventDelivery(event: event, receiver: pid).send()
                            },
                            preservePointer: @MainActor () -> (@MainActor () -> Void) = {
                                let guardObject = MenuBarPointerGuard()
                                return { guardObject.restore() }
                            },
                            wait: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) async -> Bool {
        guard !Task.isCancelled, receiver > 0, let window, let destination,
              let source = CGEventSource(stateID: .hidSystemState) else { return false }
        let toHidden = to.x < destination.frame.midX
        let edge = toHidden ? destination.frame.minX : destination.frame.maxX
        let rightward = window.frame.minX < edge
        let pickup = CGPoint(x: edge + (rightward ? 0 : (toHidden ? -1 : 1)), y: destination.frame.minY)
        let drop = CGPoint(x: edge - (rightward ? window.frame.width : 0), y: destination.frame.minY)
        guard let down = dragEvent(.leftMouseDown, at: pickup, target: window, receiver: receiver, source: source),
              let up = dragEvent(.leftMouseUp, at: drop, target: destination, receiver: receiver, source: source) else { return false }
        source.localEventsSuppressionInterval = 0
        down.setIntegerValueField(.mouseEventClickState, value: 0)
        up.setIntegerValueField(.mouseEventClickState, value: 0)
        let restorePointer = preservePointer()
        defer { restorePointer() }
        do {
            try await deliver(down, receiver)
            try await wait(80_000_000)
            try Task.checkCancellation()
            try await deliver(up, receiver)
            return true
        } catch {
            // Release even after cancellation or a missing acknowledgement; never leave a live drag.
            await Task { @MainActor in try? await deliver(up, receiver) }.value
            return false
        }
    }
}
