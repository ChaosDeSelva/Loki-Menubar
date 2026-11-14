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
        check("Symbol-only title falls back to the owner", MenuLabel.resolve(identifier: "", title: "●", description: "", help: "", owner: "Feedback Graph", system: false) == "Feedback Graph")
        check("Symbol-only title yields to a real description", MenuLabel.resolve(identifier: "", title: "●", description: "Status", help: "", owner: "Example", system: false) == "Status")
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
        typealias S = MenuBarSections
        check("Idle divider takes no space", S.dividerLength(.idle) == 0)
        check("Collapsed divider pushes icons off-screen", S.dividerLength(.collapsed) >= 5_000)
        check("Revealed and arranging dividers are a drop target", S.dividerLength(.revealed) > 0 && S.dividerLength(.arranging) == S.dividerLength(.revealed))
        let rune = CGRect(x: 1300, y: 0, width: 30, height: 24)
        check("Divider left of rune is valid", S.orderingValid(divider: CGRect(x: 1280, y: 0, width: 16, height: 24), anchor: rune))
        check("Divider right of rune is refused", !S.orderingValid(divider: CGRect(x: 1340, y: 0, width: 16, height: 24), anchor: rune))
        check("Zero-width divider is refused", !S.orderingValid(divider: CGRect(x: 1280, y: 0, width: 0, height: 24), anchor: rune))
        let placements = [S.Placement(id: "left-chosen", midX: 900), S.Placement(id: "left-unchosen", midX: 950),
                          S.Placement(id: "right-chosen", midX: 1100), S.Placement(id: "right-unchosen", midX: 1150)]
        check("Only misplaced icons move", S.moves(items: placements, dividerMidX: 1000, hidden: ["left-chosen", "right-chosen"])
              == [S.Move(id: "left-unchosen", toHidden: false), S.Move(id: "right-chosen", toHidden: true)])
        check("Empty choice reveals everything", S.moves(items: placements, dividerMidX: 1000, hidden: []).allSatisfy { !$0.toHidden })
        check("Settled layout needs no moves", S.moves(items: [S.Placement(id: "a", midX: 900)], dividerMidX: 1000, hidden: ["a"]).isEmpty)
        let line = CGRect(x: 1000, y: 0, width: 16, height: 24)
        // Measured on macOS 26.5: a Command-drag released on or just past the divider lands one slot short.
        check("Hidden drop overshoots the divider's left edge", S.dropPoint(divider: line, toHidden: true, attempt: 0).x <= line.minX - S.dropOvershoot)
        check("Visible drop overshoots the divider's right edge", S.dropPoint(divider: line, toHidden: false, attempt: 0).x >= line.maxX + S.dropOvershoot)
        check("Retries reach further", S.dropPoint(divider: line, toHidden: true, attempt: 1).x < S.dropPoint(divider: line, toHidden: true, attempt: 0).x
              && S.dropPoint(divider: line, toHidden: false, attempt: 1).x > S.dropPoint(divider: line, toHidden: false, attempt: 0).x)
        // Collapsed: the divider runs from -3923 to 1079 and pushes hidden icons further left still.
        let wide = CGRect(x: -3923, y: 4, width: 5002, height: 24), display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        check("Collapsed bar keeps icons pushed past the divider's left edge", S.onCollapsedBar(CGRect(x: -4183, y: 4, width: 33, height: 24), divider: wide, display: display))
        check("Collapsed bar keeps visible icons", S.onCollapsedBar(CGRect(x: 1085, y: 4, width: 36, height: 24), divider: wide, display: display))
        check("Collapsed bar refuses other rows and other displays", !S.onCollapsedBar(CGRect(x: 1085, y: 300, width: 36, height: 24), divider: wide, display: display)
              && !S.onCollapsedBar(CGRect(x: 1600, y: 4, width: 36, height: 24), divider: wide, display: display))
        check("Pushed-past icons read as hidden", S.moves(items: [S.Placement(id: "a", midX: -4166)], dividerMidX: wide.midX, hidden: ["a"]).isEmpty
              && S.moves(items: [S.Placement(id: "a", midX: -4166)], dividerMidX: wide.midX, hidden: []) == [S.Move(id: "a", toHidden: false)])
        check("Drop stays on the divider's row", S.dropPoint(divider: line, toHidden: true, attempt: 0).y == line.midY)
        check("Pinned system icons are not offered", !S.movable("menu:system:clock") && !S.movable("menu:system:controlcenter") && S.movable("menu:system:wifi"))
        check("Rehide waits for idle delay", !S.shouldRehide(pointerInBar: false, menuOpen: false, mouseDown: false, commandHeld: false, idle: 2, delay: 3))
        check("Rehide after idle delay", S.shouldRehide(pointerInBar: false, menuOpen: false, mouseDown: false, commandHeld: false, idle: 3, delay: 3))
        for (name, inBar, menu, down, command) in [("pointer in bar", true, false, false, false), ("open menu", false, true, false, false),
                                                   ("mouse down", false, false, true, false), ("Command held", false, false, false, true)] {
            check("Rehide blocked by \(name)", !S.shouldRehide(pointerInBar: inBar, menuOpen: menu, mouseDown: down, commandHeld: command, idle: 60, delay: 3))
        }
        check("AppKit frames flip to top-left origin", S.flipped(CGRect(x: 10, y: 876, width: 16, height: 24), primaryHeight: 900) == CGRect(x: 10, y: 0, width: 16, height: 24))
        var chosen = Preferences()
        chosen.realms[0].hiddenItems = ["menu:system:wifi"]
        let chosenReloaded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(chosen))
        check("Hidden icons persist independently per realm", chosenReloaded.realms[0].hiddenItems == ["menu:system:wifi"] && chosenReloaded.realms[1].hiddenItems == nil)
        var alpha5 = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Preferences())) as! [String: Any]
        alpha5["realms"] = (alpha5["realms"] as! [[String: Any]]).map { var r = $0; r["tuckedApps"] = ["com.example.app"]; return r }
        let upgraded = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: alpha5))
        check("Alpha 5 app allowlist is read and ignored", upgraded.realms.allSatisfy { $0.hiddenItems == nil })
        let unmanaged = ManagedPolicy([:])
        check("No profile means nothing managed", !unmanaged.isManaged && unmanaged.apply(to: chosen).realms == chosen.realms)
        let managed = ManagedPolicy(["HiddenItems": ["menu:system:wifi", " menu:system:wifi ", "", "menu:system:battery"], "AutoRehide": false,
                                     "RehideDelay": 90, "HoverReveal": true, "DisableUpdates": true, "AutomaticUpdateChecks": false,
                                     "DisableHiding": false, "LaunchAtLogin": true, "Unrelated": 1])
        check("Managed keys are listed sorted", managed.managedKeys == ManagedPolicy.keys.sorted() && managed.ignoredKeys.isEmpty)
        check("Managed hidden list is trimmed and deduplicated", managed.hiddenItems == ["menu:system:wifi", "menu:system:battery"])
        check("Managed delay clamps high", managed.rehideDelay == 30)
        check("Managed delay clamps low", ManagedPolicy(["RehideDelay": 0.2]).rehideDelay == 1)
        let overlaid = managed.apply(to: chosen)
        check("Managed hidden list applies to every realm", overlaid.realms.allSatisfy { $0.hiddenItems == ["menu:system:wifi", "menu:system:battery"] })
        check("Managed hiding settings overlay preferences", overlaid.rehideDelay == 30 && overlaid.autoRehide == false && overlaid.hoverReveal == true)
        check("Overlay keeps the user's saved choices", chosen.realms[1].hiddenItems == nil && overlaid.realms.map(\.pins) == chosen.realms.map(\.pins))
        let wrong = ManagedPolicy(["HiddenItems": ["ok", 3], "AutoRehide": "yes", "RehideDelay": true, "DisableHiding": 1,
                                   "DisableUpdates": "true", "LaunchAtLogin": [true], "HoverReveal": Double.nan])
        check("Wrong types are ignored", !wrong.isManaged && wrong.hiddenItems == nil && wrong.autoRehide == nil && wrong.rehideDelay == nil
              && !wrong.disableHiding && !wrong.disableUpdates && wrong.launchAtLogin == nil && wrong.hoverReveal == nil)
        check("Ignored keys are reported", wrong.ignoredKeys == ["AutoRehide", "DisableHiding", "DisableUpdates", "HiddenItems", "HoverReveal", "LaunchAtLogin", "RehideDelay"])
        check("Non-finite delay is ignored", ManagedPolicy(["RehideDelay": Double.infinity]).rehideDelay == nil)
        check("Empty managed list unhides everything", ManagedPolicy(["HiddenItems": [String]()]).apply(to: chosen).realms.allSatisfy { $0.hiddenItems == [] })
        let suite = "loki-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "DisableHiding")
        check("User defaults are not treated as managed", !ManagedPolicy.read(from: defaults).isManaged)

        // macOS 27 allowlist planning: item ownership.
        check("Owner of identified extra", S.owner(ofItem: "menu:com.example.app:upload") == "com.example.app")
        check("Owner of slot extra", S.owner(ofItem: "menu-slot:com.example.app:2") == "com.example.app")
        check("Identifier colons stay in the identifier", S.owner(ofItem: "menu:com.example.app:a:b::c") == "com.example.app")
        check("System controls have no owner", S.owner(ofItem: "menu:system:wifi") == nil && S.owner(ofItem: "menu-slot:system:0") == nil)
        check("App IDs are not menu extras", S.owner(ofItem: "app:com.example.app") == nil)
        for bad in ["", ":", "::", "menu", "menu:", "menu::id", "menu:com.example.app", "menu:com.example.app:", "Menu:com.example.app:x",
                    "menuslot:com.example.app:1", "pin:com.example.app:x", " menu:com.example.app:x"] {
            check("Malformed ID has no owner: '\(bad)'", S.owner(ofItem: bad) == nil)
        }
        for (bundle, identifier, slot) in [("com.example.app", "upload", 0), ("com.example.app", "", 3), ("org.x.Tool", "a:b:c", 1),
                                           ("com.example.app", ":", 0), ("com.example.app", "::lead", 0), ("io.y", "", 0)] {
            let id = MenuIdentity.thirdParty(bundle: bundle, identifier: identifier, slot: slot)
            check("Third-party ID round-trips its owner: \(id)", S.owner(ofItem: id) == bundle)
        }
        for (identifier, title) in [("com.apple.menuextra.wifi", ""), ("", "Clock"), ("battery", "Battery"), ("", ""), ("x:y", "Odd:Title"),
                                    ("com.apple.menuextra.controlcenter", "Control Center")] {
            let id = MenuLabel.systemID(identifier: identifier, title: title)
            check("System ID has no owner: \(id)", S.owner(ofItem: id) == nil)
        }

        // macOS 27 allowlist planning: which running apps stay allowed.
        let own = "io.github.ChaosDeSelva.Loki"
        let running = ["com.example.b", "com.example.a", "com.apple.controlcenter", "com.example.c"]
        check("Empty choice allows every running app and Loki",
              S.allowedBundles(running: running, hiddenItems: [], ownBundle: own) == (running + [own]).sorted())
        check("Choosing one icon hides its app",
              S.allowedBundles(running: running, hiddenItems: ["menu:com.example.a:upload"], ownBundle: own) == ["com.apple.controlcenter", "com.example.b", "com.example.c", own].sorted())
        check("Slot IDs hide their app too",
              !S.allowedBundles(running: running, hiddenItems: ["menu-slot:com.example.b:0"], ownBundle: own).contains("com.example.b"))
        check("Several icons of one app hide it once",
              S.allowedBundles(running: running, hiddenItems: ["menu:com.example.a:x", "menu:com.example.a:y", "menu-slot:com.example.a:1"], ownBundle: own)
              == S.allowedBundles(running: running, hiddenItems: ["menu:com.example.a:x"], ownBundle: own))
        check("Loki is never hidden", S.allowedBundles(running: running + [own], hiddenItems: ["menu:\(own):rune", "menu-slot:\(own):0"], ownBundle: own).contains(own))
        check("Loki is allowed even when not listed as running", S.allowedBundles(running: [], hiddenItems: [], ownBundle: own) == [own])
        check("Apple apps are never hidden",
              S.allowedBundles(running: running, hiddenItems: ["menu:com.apple.controlcenter:wifi", "menu:com.apple.Siri:x"], ownBundle: own).contains("com.apple.controlcenter"))
        check("Duplicates are removed and output sorted",
              S.allowedBundles(running: ["z.app", "a.app", "z.app", own, "a.app"], hiddenItems: [], ownBundle: own) == ["a.app", own, "z.app"].sorted())
        check("System IDs do not change the allowlist",
              S.allowedBundles(running: running, hiddenItems: ["menu:system:wifi", "menu:system:clock", "app:com.example.a"], ownBundle: own)
              == S.allowedBundles(running: running, hiddenItems: [], ownBundle: own))
        check("Chosen apps that are not running are not added",
              S.allowedBundles(running: running, hiddenItems: ["menu:com.absent.app:x"], ownBundle: own) == (running + [own]).sorted())
        let mixed = S.allowedBundles(running: running, hiddenItems: ["menu:com.example.a:x", "menu:com.example.c:y", "menu:system:wifi"], ownBundle: own)
        check("Allowlist is a sorted subset of running plus Loki",
              mixed == mixed.sorted() && Set(mixed).isSubset(of: Set(running + [own])) && Set(mixed).count == mixed.count)
        check("Allowlist drops exactly the chosen apps", Set(running + [own]).subtracting(mixed) == ["com.example.a", "com.example.c"])

        // What the checklist may offer on each backend.
        check("Allowlist offers third-party icons", S.hideable("menu:com.example.app:x", allowlist: true) && S.hideable("menu-slot:com.example.app:0", allowlist: true))
        check("Allowlist refuses Apple-owned icons", !S.hideable("menu:com.apple.controlcenter:wifi", allowlist: true) && !S.hideable("menu-slot:com.apple.Siri:0", allowlist: true))
        check("Allowlist refuses system controls", ["menu:system:wifi", "menu:system:clock", "menu:system:battery"].allSatisfy { !S.hideable($0, allowlist: true) })
        check("Allowlist refuses malformed IDs", !S.hideable("", allowlist: true) && !S.hideable("app:com.example.app", allowlist: true))
        check("Divider refuses pinned system icons", !S.hideable("menu:system:clock", allowlist: false) && !S.hideable("menu:system:controlcenter", allowlist: false))
        check("Divider offers other system icons", S.hideable("menu:system:wifi", allowlist: false) && S.hideable("menu:system:battery", allowlist: false))
        check("Divider offers third-party icons", S.hideable("menu:com.example.app:x", allowlist: false) && S.hideable("menu-slot:com.example.app:0", allowlist: false))
        let sample = ["menu:com.example.app:x", "menu-slot:com.example.b:1", "menu:com.apple.Siri:x", "menu:system:wifi", "menu:system:clock", ""]
        check("Anything hideable on the allowlist has an owner that can actually be hidden",
              sample.filter { S.hideable($0, allowlist: true) }.allSatisfy { id in
                  let owner = S.owner(ofItem: id)!
                  return !S.allowedBundles(running: [owner], hiddenItems: [id], ownBundle: own).contains(owner)
              })

        // Managed hidden lists pass through the same planning.
        let profile = ManagedPolicy(["HiddenItems": ["menu:com.example.a:x", "menu:system:clock", "menu:com.apple.Siri:x", "menu:system:wifi", "menu:\(own):rune"]])
        let offered = profile.hiddenItems!.filter { S.hideable($0, allowlist: true, ownBundle: own) }
        check("Managed list is filtered to hideable items on the allowlist", offered == ["menu:com.example.a:x"])
        check("Loki's own icons are never hideable", !S.hideable("menu:\(own):rune", allowlist: true, ownBundle: own) && !S.hideable("menu:\(own):rune", allowlist: false, ownBundle: own))
        check("Managed list is filtered to hideable items on the divider",
              profile.hiddenItems!.filter { S.hideable($0, allowlist: false, ownBundle: own) } == ["menu:com.example.a:x", "menu:com.apple.Siri:x", "menu:system:wifi"])
        check("Managed list never hides Loki or Apple on the allowlist",
              S.allowedBundles(running: running + ["com.apple.Siri"], hiddenItems: Set(profile.hiddenItems!), ownBundle: own)
              == ["com.apple.Siri", "com.apple.controlcenter", "com.example.b", "com.example.c", own].sorted())

        // moves(): stability and boundaries.
        check("Icon exactly at divider counts as visible", S.moves(items: [S.Placement(id: "edge", midX: 1000)], dividerMidX: 1000, hidden: []).isEmpty
              && S.moves(items: [S.Placement(id: "edge", midX: 1000)], dividerMidX: 1000, hidden: ["edge"]) == [S.Move(id: "edge", toHidden: true)])
        check("Chosen IDs that are not on screen produce no moves", S.moves(items: [], dividerMidX: 1000, hidden: ["ghost"]).isEmpty)
        check("Moves preserve item order", S.moves(items: placements.reversed(), dividerMidX: 1000, hidden: ["right-chosen"]).map(\.id) == ["right-chosen", "left-unchosen", "left-chosen"])
        var rng = SystemRandomNumberGenerator()
        var settledOK = true, monotone = true
        for _ in 0..<200 {
            let divider = CGFloat(Int.random(in: 500...1500, using: &rng))
            let items = (0..<Int.random(in: 0...12, using: &rng)).map { S.Placement(id: "i\($0)", midX: CGFloat(Int.random(in: 0...2000, using: &rng))) }
            let picked = Set(items.map(\.id).filter { _ in Bool.random(using: &rng) })
            let planned = S.moves(items: items, dividerMidX: divider, hidden: picked)
            if planned.contains(where: { $0.toHidden != picked.contains($0.id) }) { monotone = false }
            let toHidden = Dictionary(uniqueKeysWithValues: planned.map { ($0.id, $0.toHidden) })
            let settled = items.map { item -> S.Placement in
                guard let hide = toHidden[item.id] else { return item }
                return S.Placement(id: item.id, midX: hide ? divider - 1 : divider + 1)
            }
            if !S.moves(items: settled, dividerMidX: divider, hidden: picked).isEmpty { settledOK = false }
        }
        check("Every move heads toward the chosen side", monotone)
        check("Applying the planned moves leaves nothing to move", settledOK)
        let forcedSuite = "loki-tests-forced-\(UUID().uuidString)"
        let forcedDefaults = UserDefaults(suiteName: forcedSuite)!
        forcedDefaults.set(["menu:com.example.app:x"], forKey: "HiddenItems")
        forcedDefaults.set(true, forKey: "DisableUpdates")
        forcedDefaults.set(true, forKey: "HoverReveal")
        let forcedPolicy = ManagedPolicy.read(from: forcedDefaults, isForced: { $0 != "HoverReveal" })
        check("Only profile-forced keys are managed", forcedPolicy.managedKeys == ["DisableUpdates", "HiddenItems"] && forcedPolicy.hiddenItems == ["menu:com.example.app:x"])
        forcedDefaults.removePersistentDomain(forName: forcedSuite)
        check("Unmanaged Mac reads no policy", !ManagedPolicy.current.isManaged || !ManagedPolicy.current.managedKeys.isEmpty)
        check("Group errors explain themselves", GroupNameError("Use another name.").errorDescription == "Use another name." && (GroupNameError("x") as Error).localizedDescription == "x")
        check("Preferences live in Application Support", PreferenceStore().url.path.hasSuffix("Application Support/Loki/preferences.json"))
        var orphaned = Realm.defaults[0]
        orphaned.groupNames = ["Work"]; orphaned.groups = ["a": "Legacy"]
        check("Groups only present in assignments are still listed", orphaned.availableGroups == ["Work", "Legacy"])
        do { _ = try orphaned.setGroupName("New", replacing: "Gone"); check("Renaming a removed group is refused", false) }
        catch { check("Renaming a removed group is refused", error.localizedDescription == "This group no longer exists.") }
        var aliasMove = Preferences()
        aliasMove.realms[0].groups = ["old-id": "Work"]
        check("Alias migration carries a group to an unassigned new ID", aliasMove.migrateItemAliases(["old-id": "new-id"]) && aliasMove.realms[0].groups == ["new-id": "Work"])
        var mirrored = Preferences()
        mirrored.realms[0].groups = ["menu:system:wifi": "Home", "menu:com.apple.controlcenter:com.apple.controlcenter.WiFi": "Work", "menu:example:z": "Work", "menu:example:a": "Home"]
        _ = mirrored.migrateSystemItemIDs()
        check("Canonical system assignment wins over a mirrored legacy host", mirrored.realms[0].groups?["menu:system:wifi"] == "Home" && mirrored.realms[0].groups?.count == 3)
        var partial = Realm.defaults[0]; partial.order = ["b"]
        let ordered = ShelfRecord(id: "b", title: "Same", app: "x"), unordered = ShelfRecord(id: "a", title: "Same", app: "x")
        check("Stored order beats unordered items", ShelfEngine.arrange([unordered, ordered], realm: partial, query: "", favoritesOnly: false) == ["b", "a"])
        check("Equal titles fall back to stable IDs", ShelfEngine.arrange([ShelfRecord(id: "z", title: "Same", app: "x"), unordered], realm: Realm.defaults[0], query: "", favoritesOnly: false) == ["a", "z"])
        check("Third-party titles are kept and trimmed to 100 characters", MenuLabel.resolve(identifier: "", title: String(repeating: "t", count: 150), description: "", help: "", owner: "Owner", system: false)?.count == 100)
        check("Bare Control Center identifier resolves", MenuLabel.resolve(identifier: "com.apple.controlcenter", title: "", description: "", help: "", owner: "", system: true) == "Control Center")
        print("\(passed) tests passed")
    }
}
