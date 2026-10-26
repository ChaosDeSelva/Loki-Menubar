import Foundation
import CoreGraphics

/// Pure planning for public-API hiding. A divider status item sits left of Loki's rune.
/// Icons left of it are the hidden section; widening the divider pushes them off-screen.
/// No AppKit here, so every decision is covered by the regression suite.
enum MenuBarSections {
    static let shownWidth: CGFloat = 16
    /// macOS clamps this (5,000 on macOS 27); any value wider than the displays works.
    static let collapsedWidth: CGFloat = 10_000

    enum Mode: Equatable { case idle, collapsed, revealed, arranging }

    /// Idle means nothing is chosen: the divider takes no space at all.
    static func dividerLength(_ mode: Mode) -> CGFloat {
        switch mode {
        case .idle: return 0
        case .collapsed: return collapsedWidth
        case .revealed, .arranging: return shownWidth
        }
    }

    /// The divider must sit left of the rune, or widening it would push the rune away too.
    static func orderingValid(divider: CGRect, anchor: CGRect) -> Bool {
        divider.width > 0 && anchor.width > 0 && divider.midX < anchor.midX
    }

    struct Placement: Equatable {
        var id: String
        var midX: CGFloat
    }

    struct Move: Equatable {
        var id: String
        var toHidden: Bool
    }

    /// Items on the wrong side of the divider. The chosen list is the source of truth:
    /// anything not chosen belongs right of the divider, where it stays visible.
    static func moves(items: [Placement], dividerMidX: CGFloat, hidden: Set<String>) -> [Move] {
        items.compactMap { item in
            let isHidden = item.midX < dividerMidX
            let wantHidden = hidden.contains(item.id)
            return isHidden == wantHidden ? nil : Move(id: item.id, toHidden: wantHidden)
        }
    }

    /// A Command-drag dropped on the divider's left edge lands to its left; the right edge, to its right.
    static func dropPoint(divider: CGRect, toHidden: Bool) -> CGPoint {
        let inset = min(3, divider.width / 4)
        return CGPoint(x: toHidden ? divider.minX + inset : divider.maxX - inset, y: divider.midY)
    }

    /// macOS pins these in place; offering them would only produce a failed drag.
    static func movable(_ id: String) -> Bool {
        !["menu:system:clock", "menu:system:controlcenter"].contains(id)
    }

    static func shouldRehide(pointerInBar: Bool, menuOpen: Bool, mouseDown: Bool, commandHeld: Bool,
                             idle: TimeInterval, delay: TimeInterval) -> Bool {
        !pointerInBar && !menuOpen && !mouseDown && !commandHeld && idle >= delay
    }

    /// AppKit frames start at the primary display's bottom-left; CGEvent and Accessibility use its top-left.
    static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: macOS 27 allowlist backend

    /// The app that owns a third-party menu extra ID; nil for system controls.
    /// IDs are `menu:<bundle>:<identifier>` or `menu-slot:<bundle>:<slot>` (see MenuIdentity).
    static func owner(ofItem id: String) -> String? {
        let parts = id.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == "menu" || parts[0] == "menu-slot", parts[1] != "system", !parts[1].isEmpty else { return nil }
        return parts[1]
    }

    /// macOS 27's allowlist hides whole apps. Running apps stay allowed unless one of their
    /// icons was chosen; Loki and Apple's own controls are always allowed.
    static func allowedBundles(running: [String], hiddenItems: Set<String>, ownBundle: String) -> [String] {
        let hidden = Set(hiddenItems.compactMap(owner(ofItem:)))
        return Set(running + [ownBundle]).filter { !hidden.contains($0) || $0 == ownBundle || $0.hasPrefix("com.apple.") }.sorted()
    }

    /// What the checklist may offer on each backend: the allowlist cannot hide single system controls.
    /// Loki's own icons are never hideable: the rune is how hidden icons come back.
    static func hideable(_ id: String, allowlist: Bool, ownBundle: String = "io.github.ChaosDeSelva.Loki") -> Bool {
        if owner(ofItem: id) == ownBundle { return false }
        return allowlist ? owner(ofItem: id).map { !$0.hasPrefix("com.apple.") } ?? false : movable(id)
    }
}
