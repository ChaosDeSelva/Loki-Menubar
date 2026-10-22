import AppKit
#if SWIFT_PACKAGE
import LokiMenuBarBridge
#endif

final class MenuBarVisibility {
    private let bridge = LOKMenuBarBridge()
    // Reflect the runtime's CaseIterable enum rather than guessing raw values.
    // Failure to resolve it disables hiding, preserving every system control.
    private static let systemItems: [NSNumber] = {
        guard LOKMenuBarBridge.available,
              let type = _typeByName("17MenuBarClientCore22MBSystemItemIdentifierO") as? any CaseIterable.Type else { return [] }
        var items: [NSNumber] = []
        for value in type.allCases {
            guard let raw = (value as? any RawRepresentable)?.rawValue as? Int else { return [] }
            items.append(NSNumber(value: raw))
        }
        return items
    }()
    static var available: Bool { LOKMenuBarBridge.available && !systemItems.isEmpty }
    func hide(_ bundles: Set<String>, completion: @escaping (String?) -> Void) {
        guard Self.available else { completion("Icon hiding is unavailable on this macOS build."); return }
        let allowed = VisibilityPlan.allowed(running: NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier),
            hidden: bundles, ownBundle: Bundle.main.bundleIdentifier ?? "io.github.ChaosDeSelva.Loki")
        bridge.applyAllowedBundles(allowed, systemItems: Self.systemItems) { error in completion(error?.localizedDescription) }
    }
    func reveal() { bridge.invalidate() }
}
