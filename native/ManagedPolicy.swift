import Foundation

/// Settings an organization enforces through a configuration profile (docs/MDM.md).
///
/// macOS delivers a profile's custom settings for the `io.github.ChaosDeSelva.Loki`
/// domain as managed preferences. `UserDefaults` reads them like any other value, and
/// `objectIsForced(forKey:)` tells them apart from the user's own defaults. Only forced
/// keys count as managed. A value of the wrong type is ignored, never trusted, and
/// never fatal. The policy is read once at launch; a changed profile applies on relaunch.
///
/// Keys:
/// - `HiddenItems` ([String]): menu-extra IDs (see `Loki --list-items`) hidden in every
///   realm. The hidden-icons checklist is locked while this is set.
/// - `AutoRehide` (Bool): hide icons again after the pointer leaves the menu bar.
/// - `RehideDelay` (Number): seconds before icons hide again, clamped to 1 through 30.
/// - `HoverReveal` (Bool): show hidden icons when the pointer touches the menu bar.
/// - `DisableUpdates` (Bool): no update checks and no update controls.
/// - `AutomaticUpdateChecks` (Bool): force automatic update checks on or off.
/// - `DisableHiding` (Bool): Loki never moves or hides menu-bar icons.
/// - `LaunchAtLogin` (Bool): informational. Locks the toggle; deliver the login item
///   itself with the profile's managed login items payload.
struct ManagedPolicy: Equatable {
    static let keys = ["HiddenItems", "AutoRehide", "RehideDelay", "HoverReveal",
                       "DisableUpdates", "AutomaticUpdateChecks", "DisableHiding", "LaunchAtLogin"]
    static let delayRange: ClosedRange<Double> = 1...30

    var hiddenItems: [String]?
    var autoRehide: Bool?
    var rehideDelay: Double?
    var hoverReveal: Bool?
    var disableUpdates = false
    var automaticUpdateChecks: Bool?
    var disableHiding = false
    var launchAtLogin: Bool?
    /// Keys that took effect, sorted.
    private(set) var managedKeys: [String] = []
    /// Known keys that were supplied with an unusable type, sorted.
    private(set) var ignoredKeys: [String] = []

    var isManaged: Bool { !managedKeys.isEmpty }

    init(_ values: [String: Any] = [:]) {
        for key in Self.keys {
            guard let value = values[key] else { continue }
            var used = true
            switch key {
            case "HiddenItems":
                if let ids = Self.strings(value) { hiddenItems = ids } else { used = false }
            case "RehideDelay":
                if let delay = Self.number(value) { rehideDelay = min(max(delay, Self.delayRange.lowerBound), Self.delayRange.upperBound) } else { used = false }
            default:
                guard let flag = Self.bool(value) else { used = false; break }
                switch key {
                case "AutoRehide": autoRehide = flag
                case "HoverReveal": hoverReveal = flag
                case "DisableUpdates": disableUpdates = flag
                case "AutomaticUpdateChecks": automaticUpdateChecks = flag
                case "DisableHiding": disableHiding = flag
                default: launchAtLogin = flag
                }
            }
            if used { managedKeys.append(key) } else { ignoredKeys.append(key) }
        }
        managedKeys.sort(); ignoredKeys.sort()
    }

    /// Reads only the keys an installed profile forces for this app's domain.
    static var current: ManagedPolicy { read(from: .standard) }

    /// `isForced` defaults to the profile check; tests substitute it, since forcing a key
    /// for real needs an MDM-installed configuration profile.
    static func read(from defaults: UserDefaults, isForced: ((String) -> Bool)? = nil) -> ManagedPolicy {
        var forced: [String: Any] = [:]
        for key in keys where isForced?(key) ?? defaults.objectIsForced(forKey: key) {
            if let value = defaults.object(forKey: key) { forced[key] = value }
        }
        return ManagedPolicy(forced)
    }

    /// Overlays managed values. The user's own choices stay saved underneath, so
    /// removing the profile restores them.
    func apply(to preferences: Preferences) -> Preferences {
        var result = preferences
        result.realms = result.realms.map(apply(to:))
        if let rehideDelay { result.rehideDelay = rehideDelay }
        if let autoRehide { result.autoRehide = autoRehide }
        if let hoverReveal { result.hoverReveal = hoverReveal }
        return result
    }

    func apply(to realm: Realm) -> Realm {
        var result = realm
        if let hiddenItems { result.hiddenItems = hiddenItems }
        return result
    }

    // Property lists carry Booleans and numbers as NSNumber. Tell them apart so a
    // number never passes as a Boolean or the reverse.
    private static func bool(_ value: Any) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func number(_ value: Any) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func strings(_ value: Any) -> [String]? {
        guard let array = value as? [Any] else { return nil }
        var seen = Set<String>()
        var ids: [String] = []
        for element in array {
            guard let id = (element as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
            if !id.isEmpty, seen.insert(id).inserted { ids.append(id) }
        }
        return ids
    }
}
