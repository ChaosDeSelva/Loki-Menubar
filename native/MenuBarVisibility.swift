import AppKit
#if SWIFT_PACKAGE
import LokiMenuBarBridge
#endif

/// macOS 27 only: Apple's undocumented MenuBarClientCore allowlist, the one mechanism that
/// hides menu-bar icons there. Resolved at runtime; absent or changed, hiding stays off.
final class MenuBarVisibility {
    private let bridge = LOKMenuBarBridge()
    // Reflect the runtime's CaseIterable enum rather than guessing raw values.
    // Failure to resolve it disables hiding, preserving every system control.
    private static let systemItems: [NSNumber] = {
        guard LOKMenuBarBridge.available,
              let type = _typeByName("17MenuBarClientCore22MBSystemItemIdentifierO") as? any CaseIterable.Type else { return [] }
        var known: [Int] = []
        for value in type.allCases {
            guard let raw = (value as? any RawRepresentable)?.rawValue as? Int else { return [] }
            known.append(raw)
        }
        // Allow every identifier the system might use, not only the cases this build reflects:
        // other menu-bar managers report that a narrower range silently drops Screen Mirroring.
        return Set(known + Array(0...255)).sorted().map { NSNumber(value: $0) }
    }()
    static var available: Bool { LOKMenuBarBridge.available && !systemItems.isEmpty }
    /// `items` are menu-extra IDs; the allowlist hides every icon of the apps that own them.
    func hide(_ items: Set<String>, completion: @escaping (String?) -> Void) {
        guard Self.available else { completion("Icon hiding is unavailable on this macOS build."); return }
        // Allow every installed app, not only running ones: an app opened while icons are hidden
        // must already be on the list, or macOS 27 hides it until the next refresh.
        let candidates = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier) + Self.installedBundles()
        let allowed = MenuBarSections.allowedBundles(running: candidates,
            hiddenItems: items, ownBundle: Bundle.main.bundleIdentifier ?? "io.github.ChaosDeSelva.Loki")
        bridge.applyAllowedBundles(allowed, systemItems: Self.systemItems) { error in completion(error?.localizedDescription) }
    }
    func reveal() { bridge.invalidate() }

    /// Bundle IDs of apps in the standard folders, including their bundled helper apps,
    /// which often own the menu-bar icon (login items, agents).
    static func installedBundles() -> [String] {
        let fm = FileManager.default
        let roots = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                     fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        var found: [String] = []
        for root in roots {
            for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where name.hasSuffix(".app") {
                let app = URL(fileURLWithPath: root).appendingPathComponent(name)
                var bundles = [app]
                for nested in ["Contents/Library/LoginItems", "Contents/Helpers", "Contents/MacOS", "Contents/Resources"] {
                    let folder = app.appendingPathComponent(nested)
                    bundles += ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".app") }.map { folder.appendingPathComponent($0) }
                }
                found += bundles.compactMap { Bundle(url: $0)?.bundleIdentifier }
            }
        }
        return found
    }
}
