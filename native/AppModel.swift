import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published var preferences = Preferences()
    @Published var items: [ShelfItem] = []
    /// Menu extras for the hidden-icons picker, scanned whatever the shelf's source is.
    @Published var menuExtras: [ShelfItem] = []
    @Published var query = ""
    @Published var selectedGroup = "All"
    @Published var favoritesOnly = false
    @Published var scanning = false
    @Published var accessibility = MenuDiscovery.trusted
    @Published var notice: String?
    @Published var lastScan: Date?
    @Published var scanSummary = "Ready when you are"
    @Published var page = "shelf"
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var shortcutRegistered = false
    let visibility = VisibilityController()
    let launcher = LauncherModel()
    @Published private var deletedGroup: (realmID: String, name: String, members: [String])?
    var canUndoGroupDeletion: Bool {
        guard let deletedGroup, deletedGroup.realmID == realm.id else { return false }
        return !realm.availableGroups.contains { $0.compare(deletedGroup.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }
    /// Settings enforced by a configuration profile, read once at launch (docs/MDM.md).
    let policy = ManagedPolicy.current
    let updater: UpdateController
    var summon: (() -> Void)?
    var dismissShelf: (() -> Void)?
    private let store: PreferenceStore
    private var canSave = true
    private let actionQueue = DispatchQueue(label: "Loki.menu-actions", qos: .userInitiated)
    private let scanQueue = DispatchQueue(label: "Loki.discovery", qos: .userInitiated)
    private var observers: [NSObjectProtocol] = []
    private var refreshWork: DispatchWorkItem?
    private var extrasScanning = false

    init(store: PreferenceStore = PreferenceStore()) {
        self.store = store
        updater = UpdateController(policy: policy)
        do {
            preferences = try store.load()
            if preferences.migrateSystemItemIDs() { try store.save(preferences) }
        }
        catch { notice = error.localizedDescription; canSave = false }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didWakeNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        refresh()
    }

    var realm: Realm { policy.apply(to: preferences.realms.first(where: { $0.id == preferences.selectedRealm }) ?? Realm.defaults[0]) }
    /// What Loki acts on: saved preferences with managed values laid over them.
    var effectivePreferences: Preferences { policy.apply(to: preferences) }
    /// The icons Loki keeps hidden right now. Empty when the organization turns hiding off.
    var hiddenSet: Set<String> { policy.disableHiding ? [] : Set(realm.hiddenItems ?? []) }
    var visibleItems: [ShelfItem] {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ShelfEngine.arrange(items.map(\.record), realm: realm, query: query, favoritesOnly: favoritesOnly).compactMap { byID[$0] }.filter { selectedGroup == "All" || (realm.groups?[$0.id] ?? "Ungrouped") == selectedGroup }
    }
    var accent: Color {
        switch preferences.accent {
        case "ember": return Color(red: 1, green: 0.62, blue: 0.39)
        case "frost": return Color(red: 0.58, green: 0.79, blue: 0.98)
        default: return Color(red: 0.76, green: 0.9, blue: 0.52)
        }
    }
    var absentPins: Int { Set(realm.pins).subtracting(Set(items.map(\.id))).count }

    func save() {
        guard canSave else { notice = "Loki preserved an unreadable settings file. Open the settings folder to back it up and remove it, then relaunch."; return }
        do { try store.save(preferences) }
        catch { notice = "Could not save your changes: \(error.localizedDescription)" }
    }
    func selectRealm(_ id: String) {
        let before = hiddenSet
        preferences.selectedRealm = id; selectedGroup = "All"; query = ""; save()
        if hiddenSet != before { visibility.apply(hiddenSet) }
    }
    @discardableResult
    func setGroupName(_ name: String, replacing old: String? = nil) -> Bool {
        guard canSave, let index = preferences.realms.firstIndex(where: { $0.id == preferences.selectedRealm }) else { return false }
        do {
            var candidate = preferences
            let updated = try candidate.realms[index].setGroupName(name, replacing: old)
            try store.save(candidate)
            preferences = candidate
            if let old, selectedGroup == old { selectedGroup = updated }
            notice = nil; return true
        } catch { notice = error.localizedDescription; return false }
    }
    func removeGroup(_ name: String) {
        guard canSave, let index = preferences.realms.firstIndex(where: { $0.id == preferences.selectedRealm }) else { return }
        var candidate = preferences
        candidate.realms[index].removeGroup(name)
        do {
            try store.save(candidate)
            deletedGroup = (realm.id, name, (realm.groups ?? [:]).filter { $0.value == name }.map(\.key))
            preferences = candidate
            if selectedGroup == name { selectedGroup = "All" }
            notice = nil
        } catch { notice = "Could not save your changes: \(error.localizedDescription)" }
    }
    func undoGroupDeletion() {
        guard canSave, let deleted = deletedGroup, deleted.realmID == realm.id,
              let index = preferences.realms.firstIndex(where: { $0.id == deleted.realmID }) else { return }
        do {
            var candidate = preferences
            _ = try candidate.realms[index].setGroupName(deleted.name)
            var assignments = candidate.realms[index].groups ?? [:]
            for id in deleted.members where assignments[id] == nil { assignments[id] = deleted.name }
            candidate.realms[index].groups = assignments
            try store.save(candidate); preferences = candidate; deletedGroup = nil; notice = nil
        } catch { notice = error.localizedDescription }
    }
    func group(_ bundleID: String, name: String) {
        guard let index = preferences.realms.firstIndex(where: { $0.id == preferences.selectedRealm }) else { return }
        guard name == "Ungrouped" || realm.availableGroups.contains(name) else { return }
        var groups = preferences.realms[index].groups ?? [:]
        groups[bundleID] = name == "Ungrouped" ? nil : name
        preferences.realms[index].groups = groups; save()
    }
    func setHidden(_ id: String, hidden: Bool) {
        guard policy.hiddenItems == nil, MenuBarSections.hideable(id, allowlist: visibility.usesAllowlist), let index = preferences.realms.firstIndex(where: { $0.id == preferences.selectedRealm }) else { return }
        var selected = Set(preferences.realms[index].hiddenItems ?? [])
        if hidden { selected.insert(id) } else { selected.remove(id) }
        preferences.realms[index].hiddenItems = selected.sorted()
        save()
    }
    /// Saved choices that are not running still appear, so they can be unchosen.
    var hidingCandidates: [(id: String, title: String, owner: String, running: Bool)] {
        var rows = menuExtras.filter { MenuBarSections.hideable($0.id, allowlist: visibility.usesAllowlist) }.map { (id: $0.id, title: $0.title, owner: $0.appName, running: true) }
        let present = Set(rows.map(\.id))
        for id in realm.hiddenItems ?? [] where !present.contains(id) { rows.append((id: id, title: id, owner: "Not running", running: false)) }
        return rows.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func applyHiding() {
        guard !policy.disableHiding else { notice = "Your organization has turned off icon hiding on this Mac."; return }
        visibility.apply(hiddenSet)
    }
    func applyHidingSettings() {
        let effective = effectivePreferences
        visibility.settings(delay: effective.rehideDelay ?? 3, autoRehide: effective.autoRehide ?? true, hoverReveal: effective.hoverReveal ?? false)
    }
    func refreshExtras() {
        guard MenuDiscovery.trusted else { menuExtras = []; return }
        guard !extrasScanning else { return }
        extrasScanning = true
        scanQueue.async { [weak self] in
            let result = MenuDiscovery.scan()
            DispatchQueue.main.async {
                guard let self else { return }
                self.extrasScanning = false
                self.menuExtras = MenuDiscovery.trusted ? result.items : []
            }
        }
    }
    func pin(_ id: String) {
        guard let index = preferences.realms.firstIndex(where: { $0.id == preferences.selectedRealm }) else { return }
        if preferences.realms[index].pins.contains(id) { preferences.realms[index].pins.removeAll { $0 == id } }
        else { preferences.realms[index].pins.append(id) }
        save()
    }
    func reorder(_ id: String, before target: String) {
        guard let index = preferences.realms.firstIndex(where: { $0.id == preferences.selectedRealm }) else { return }
        let ordered = ShelfEngine.arrange(items.map(\.record), realm: realm, query: "", favoritesOnly: false)
        let absent = realm.order.filter { !ordered.contains($0) }
        preferences.realms[index].order = ShelfEngine.reordered(ordered, moving: id, before: target) + absent
        save()
    }
    func renameRealm(_ id: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = preferences.realms.firstIndex(where: { $0.id == id }) else { return }
        preferences.realms[index].name = String(trimmed.prefix(32)); save()
    }
    func source(_ source: String) { preferences.source = source; query = ""; save(); refresh() }
    func scheduleRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
    func refresh() {
        accessibility = MenuDiscovery.trusted
        if preferences.source == "apps" {
            items = MenuDiscovery.appShortcuts(); lastScan = Date(); scanSummary = "\(items.count) running apps"; return
        }
        guard accessibility else { items = []; scanSummary = "Accessibility permission needed"; return }
        guard !scanning else { return }
        scanning = true
        scanQueue.async { [weak self] in
            let result = MenuDiscovery.scan()
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                guard self.preferences.source == "menu", MenuDiscovery.trusted else { self.refresh(); return }
                if self.preferences.migrateItemAliases(result.legacyAliases) { self.save() }
                self.items = result.items
                self.menuExtras = result.items
                self.lastScan = Date()
                self.scanSummary = "\(result.items.count) menu items · \(result.scanned) processes checked"
                if result.unresponsive > 0 { self.scanSummary += " · \(result.unresponsive) busy" }
            }
        }
    }
    func requestAccessibility() {
        MenuDiscovery.requestPermission()
        preferences.source = "menu"; save()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func open(_ item: ShelfItem) {
        let wasConcealed = visibility.concealed
        visibility.reveal()
        dismissShelf?()
        if item.kind == .app {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                if let error = MenuDiscovery.activate(item) { self?.notice = error }
            }
            return
        }
        // Some owners keep AXPress pending for the lifetime of a tracking menu.
        // Never block Loki's main run loop or reopen its UI over that menu.
        actionQueue.asyncAfter(deadline: .now() + (wasConcealed ? 0.45 : 0.15)) { [weak self] in
            let error = MenuDiscovery.activate(item)
            DispatchQueue.main.async { if let error { self?.notice = error } }
        }
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        guard policy.launchAtLogin == nil else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { notice = "Approve Loki in System Settings → General → Login Items." }
        } catch { notice = "Could not change launch at login: \(error.localizedDescription)" }
    }
    func openSettingsFolder() {
        do {
            try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            NSWorkspace.shared.open(store.url.deletingLastPathComponent())
        } catch { notice = error.localizedDescription }
    }
}
