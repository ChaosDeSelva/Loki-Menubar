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
            var result = entry; result.removeValue(forKey: "groups"); result.removeValue(forKey: "tuckedApps"); return result
        }
        try JSONSerialization.data(withJSONObject: legacy).write(to: store.url)
        let migrated = try store.load()
        check("Legacy preferences remain readable", migrated.realms[0].pins == ["a"] && migrated.realms[0].groups == nil)
        print("\(passed) tests passed")
    }
}
