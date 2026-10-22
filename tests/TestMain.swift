import Foundation
import CoreGraphics

@main
enum Tests {
    static func main() throws {
        var passed = 0
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
            passed += 1; print("PASS: \(name)")
        }
        let a = ShelfRecord(id: "a", title: "Öresund VPN", app: "Network")
        let b = ShelfRecord(id: "b", title: "Wi-Fi", app: "System")
        let c = ShelfRecord(id: "c", title: "Wi-Fi Monitor", app: "Utility")
        var realm = Realm.defaults[0]
        realm.pins = ["c", "absent"]
        check("New items remain visible", Set(ShelfEngine.arrange([a, b, c], realm: realm, query: "", favoritesOnly: false)) == Set(["a", "b", "c"]))
        check("Pinned items first", ShelfEngine.arrange([a, b, c], realm: realm, query: "", favoritesOnly: false).first == "c")
        check("Exact search beats unrelated pin", ShelfEngine.arrange([c, b], realm: realm, query: "WI-FI", favoritesOnly: false) == ["b", "c"])
        check("Unicode and multiword search", ShelfEngine.arrange([a, b], realm: realm, query: "  ORESUND vpn ", favoritesOnly: false) == ["a"])
        check("Favorites exclude unpinned", ShelfEngine.arrange([a, b, c], realm: realm, query: "", favoritesOnly: true) == ["c"])
        check("Duplicate discovery coalesces", ShelfEngine.arrange([a, a], realm: realm, query: "", favoritesOnly: false) == ["a"])
        check("Missing favorites are not deleted", realm.pins == ["c", "absent"])
        realm.pins = []; realm.order = ["b", "a", "b"]
        check("Stored order is deterministic", ShelfEngine.arrange([a, b], realm: realm, query: "", favoritesOnly: false) == ["b", "a"])
        check("Drag reorders exactly once", ShelfEngine.reordered(["a", "b", "c"], moving: "c", before: "a") == ["c", "a", "b"])
        check("Unknown drag is a no-op", ShelfEngine.reordered(["a", "b"], moving: "x", before: "b") == ["a", "b"])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("loki-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PreferenceStore(url: root.appendingPathComponent("preferences.json"))
        var preferences = try store.load()
        check("Fresh install has three realms", preferences.realms.count == 3)
        preferences.realms[0].pins = ["a"]; preferences.selectedRealm = "midgard"
        try store.save(preferences)
        let loaded = try store.load()
        check("Profiles persist independently", loaded.selectedRealm == "midgard" && loaded.realms[0].pins == ["a"] && loaded.realms[1].pins.isEmpty)
        try Data("broken".utf8).write(to: store.url)
        do { _ = try store.load(); check("Corrupt state rejected", false) } catch { check("Corrupt state rejected", true) }
        let preserved = try String(contentsOf: store.url, encoding: .utf8)
        check("Corrupt file preserved", preserved == "broken")
        preferences.version = 99; try store.save(preferences)
        do { _ = try store.load(); check("Future schema rejected", false) } catch { check("Future schema rejected", true) }
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        check("Visible status item allowed", MenuGeometry.isSafe(CGRect(x: 1200, y: 0, width: 24, height: 30), on: [screen]))
        check("Apple menu region rejected", !MenuGeometry.isSafe(CGRect(x: 5, y: 0, width: 24, height: 30), on: [screen]))
        check("Offscreen hidden item rejected", !MenuGeometry.isSafe(CGRect(x: -500, y: 0, width: 24, height: 30), on: [screen]))
        check("Ordinary content area rejected", !MenuGeometry.isSafe(CGRect(x: 1200, y: 200, width: 24, height: 30), on: [screen]))
        check("Oversized accessibility item rejected", !MenuGeometry.isSafe(CGRect(x: 500, y: 0, width: 900, height: 30), on: [screen]))
        check("Negative-origin display supported", MenuGeometry.isSafe(CGRect(x: -200, y: 0, width: 24, height: 30), on: [CGRect(x: -1920, y: 0, width: 1920, height: 1080)]))
        preferences.version = 1
        preferences.realms[0].groups = ["a": "Work"]
        try store.save(preferences)
        let grouped = try store.load()
        check("Groups persist independently", grouped.realms[0].groups?["a"] == "Work" && grouped.realms[1].groups == nil)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as! [String: Any]
        legacy.removeValue(forKey: "rehideDelay"); legacy.removeValue(forKey: "autoRehide")
        legacy["realms"] = (legacy["realms"] as! [[String: Any]]).map { entry in
            var result = entry; result.removeValue(forKey: "groupNames"); result.removeValue(forKey: "groups"); result.removeValue(forKey: "tuckedApps"); return result
        }
        try JSONSerialization.data(withJSONObject: legacy).write(to: store.url)
        let migrated = try store.load()
        check("Legacy preferences remain readable", migrated.realms[0].pins == ["a"] && migrated.realms[0].groups == nil)
        check("Legacy groups retain defaults", migrated.realms[0].availableGroups == ["Work", "Personal", "System"])
        var custom = Realm.defaults[0]
        custom.groups = ["online": "Work", "offline": "Work", "other": "Personal"]
        custom.pins = ["offline"]; custom.order = ["online", "offline"]
        _ = try custom.setGroupName(" Work · Development ", replacing: "Work")
        _ = try custom.setGroupName("Work · Meetings")
        check("Multiple work groups supported", custom.availableGroups.contains("Work · Development") && custom.availableGroups.contains("Work · Meetings"))
        check("Rename retains offline assignments", custom.groups?["offline"] == "Work · Development" && custom.groups?["online"] == "Work · Development")
        for invalid in ["", "  ", "All", "ungrouped", "PERSONAL", String(repeating: "a", count: 41)] {
            let before = custom
            do { _ = try custom.setGroupName(invalid); check("Invalid group rejected", false) }
            catch { check("Invalid group leaves state intact", custom == before) }
        }
        custom.removeGroup("Work · Development")
        check("Delete only unassigns its own items", custom.groups == ["other": "Personal"] && custom.pins == ["offline"] && custom.order == ["online", "offline"])
        preferences.realms[0] = custom
        try store.save(preferences)
        let customized = try store.load()
        check("Custom names persist independently", customized.realms[0] == custom && customized.realms[1].availableGroups == ["Work", "Personal", "System"])
        for name in custom.availableGroups { custom.removeGroup(name) }
        preferences.realms[0] = custom; try store.save(preferences)
        let emptyGroups = try store.load()
        check("Deleted defaults stay deleted after restart", emptyGroups.realms[0].availableGroups.isEmpty)
        check("Specific system title beats generic host description", MenuLabel.resolve(identifier: "", title: "Wi-Fi", description: "Control Center", help: "", owner: "Control Center", system: true) == "Wi-Fi")
        check("System identifier resolves unnamed battery", MenuLabel.resolve(identifier: "com.apple.controlcenter.Battery", title: "", description: "Control Center", help: "", owner: "Control Center", system: true) == "Battery")
        check("Unknown system proxies are omitted", MenuLabel.resolve(identifier: "proxy-3", title: "", description: "", help: "", owner: "MenuBarAgent", system: true) == nil)
        check("Third party owner fallback retained", MenuLabel.resolve(identifier: "", title: "", description: "", help: "", owner: "Example", system: false) == "Example")
        check("System identity survives host fallback", MenuLabel.systemID(identifier: "com.apple.controlcenter.WiFi", title: "Wi-Fi") == MenuLabel.systemID(identifier: "", title: "Wi-Fi"))
        var migration = Preferences()
        migration.realms[0].pins = ["menu:com.apple.controlcenter:com.apple.controlcenter.WiFi", "menu:system:wifi"]
        migration.realms[0].groups = ["menu:com.apple.MenuBarAgent:Battery": "Work"]
        check("Existing system preferences migrate", migration.migrateSystemItemIDs() && migration.realms[0].pins == ["menu:system:wifi"] && migration.realms[0].groups?["menu:system:battery"] == "Work")
        check("System ID migration is idempotent", !migration.migrateSystemItemIDs())

        let stable = MenuIdentity.thirdParty(bundle: "example.utility", identifier: "", slot: 0)
        var dynamic = Preferences()
        dynamic.realms[0].pins = [stable]
        dynamic.realms[0].groups = [stable: "Work"]
        for title in ["Upload 1 KB/s", "Upload 2 KB/s"] {
            let item = ShelfRecord(id: MenuIdentity.thirdParty(bundle: "example.utility", identifier: "", slot: 0), title: title, app: "Utility")
            check("Changing title retains favorite and group", ShelfEngine.arrange([item], realm: dynamic.realms[0], query: "", favoritesOnly: true) == [stable] && dynamic.realms[0].groups?[item.id] == "Work")
        }
        check("Unnamed extras stay distinct", stable != MenuIdentity.thirdParty(bundle: "example.utility", identifier: "", slot: 1))
        check("Identified extras retain existing keys", MenuIdentity.thirdParty(bundle: "example.utility", identifier: "upload", slot: 9) == "menu:example.utility:upload")
        let legacyID = "menu:example.utility:Upload 1 KB/s"
        dynamic.realms[0].pins = [legacyID, stable]
        dynamic.realms[0].order = [legacyID]
        dynamic.realms[0].groups = [legacyID: "Personal", stable: "Work"]
        check("Legacy aliases migrate without overwriting", dynamic.migrateItemAliases([legacyID: stable]) && dynamic.realms[0].pins == [stable] && dynamic.realms[0].order == [stable] && dynamic.realms[0].groups == [stable: "Work"])
        check("Alias migration is idempotent", !dynamic.migrateItemAliases([legacyID: stable]))
        var counters: [String: Int] = [:]
        _ = MenuIdentity.nextOccurrence(identifier: "", title: "upload", counters: &counters)
        check("Unnamed labels cannot renumber identified extras", MenuIdentity.nextOccurrence(identifier: "upload", title: "Rate", counters: &counters) == 0)
        check("Duplicate identified extras remain distinct", MenuIdentity.nextOccurrence(identifier: "upload", title: "Other", counters: &counters) == 1)
        let allowed = VisibilityPlan.allowed(running: ["one", "two", "one", "com.apple.controlcenter"], hidden: ["one", "self", "com.apple.controlcenter"], ownBundle: "self")
        check("Hiding preserves owner and system controls", allowed == ["com.apple.controlcenter", "self", "two"])
        check("New apps remain visible by default", VisibilityPlan.allowed(running: ["new"], hidden: ["old"], ownBundle: "self") == ["new", "self"])
        var tucked = Preferences()
        tucked.realms[0].tuckedApps = ["one"]
        let tuckedReloaded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(tucked))
        check("Hiding selection persists independently per realm", tuckedReloaded.realms[0].tuckedApps == ["one"] && tuckedReloaded.realms[1].tuckedApps == nil)
        print("\(passed) tests passed")
    }
}
