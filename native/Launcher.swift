import AppKit
import SwiftUI
import Carbon
import Combine

@MainActor
final class LauncherModel: ObservableObject {
    @Published private(set) var settings = LauncherSettings()
    @Published private(set) var applications: [LaunchEntry] = [] { didSet { updateResults() } }
    @Published private(set) var results: [LaunchEntry] = []
    @Published private(set) var indexing = false
    @Published var query = "" { didSet { updateResults() } }
    @Published var tab = "search"
    @Published var shortcutError: String?
    @Published var settingsError: String?
    @Published var launchError: String?
    let chat: QuickChatModel
    let addons: AddOnManager
    let addonSession: AddOnSession
    var settingsChanged: (() -> Void)?
    var requestShortcut: ((LaunchShortcut) -> Bool)?
    var openPanel: (() -> Void)?
    var perform: ((LaunchEntry.Action) -> Void)?
    private let store: LauncherStore
    private var canSave = true
    private var scanID = UUID()
    private var lastScan: Date?
    private var addonObservation: AnyCancellable?

    init(store: LauncherStore = LauncherStore(), addons: AddOnManager? = nil) {
        self.store = store
        chat = QuickChatModel(historyStore: QuickChatHistoryStore(url: store.url.deletingLastPathComponent().appendingPathComponent("Chat History/history.json")))
        let addons = addons ?? AddOnManager()
        self.addons = addons; addonSession = AddOnSession(manager: addons)
        do {
            settings = try store.load()
            if settings.migrateShortcut() { try store.save(settings) }
        }
        catch { settingsError = "\(error.localizedDescription) Your launcher.json was preserved. Back it up and remove it from Loki’s settings folder to reset this add-on."; canSave = false }
        updateResults()
        addonObservation = addons.$revision.dropFirst().sink { [weak self] _ in self?.updateResults() }
    }
    static let commands: [LaunchEntry] = [
        LaunchEntry(id: "command:chat", title: "Quick Chat", subtitle: "Ask Claude or Codex", keywords: "ai assistant question", symbol: "bubble.left.and.bubble.right", action: .chat),
        LaunchEntry(id: "command:shelf", title: "Open Shelf", subtitle: "Your menu bar utilities", keywords: "loki favorites menu", symbol: "square.grid.2x2", action: .shelf),
        LaunchEntry(id: "command:settings", title: "Loki Settings", subtitle: "Preferences and add-ons", keywords: "configure shortcut launcher", symbol: "slider.horizontal.3", action: .settings),
        LaunchEntry(id: "command:reveal", title: "Reveal All Menu Bar Items", subtitle: "Show every menu bar icon", keywords: "unhide restore", symbol: "eye", action: .reveal),
        LaunchEntry(id: "command:toggle", title: "Toggle Hidden Icons", subtitle: "Show or hide your chosen icons", keywords: "menu bar", symbol: "menubar.rectangle", action: .toggleHidden)
    ]
    private func updateResults() {
        let commands = addons.packages.filter { addons.enabled($0) }.flatMap { package in
            package.manifest.commands.map { command in
                LaunchEntry(id: "addon:\(package.id):\(command.id)", title: command.title, subtitle: package.manifest.name,
                    keywords: (command.keywords ?? []).joined(separator: " ") + " " + (command.subtitle ?? ""),
                    symbol: command.icon ?? package.manifest.icon ?? "puzzlepiece.extension", action: .addon(package.id, command.id))
            }
        }
        results = Array(LauncherSearch.results(Self.commands + commands + applications, query: query).prefix(60))
    }

    @discardableResult
    func change(_ update: (inout LauncherSettings) -> Void) -> Bool {
        guard canSave else { return false }
        var candidate = settings; update(&candidate)
        guard candidate.shortcut.isValid else { settingsError = "Use Shift-Space, or include Command or Control."; return false }
        do {
            try store.save(candidate)
            let old = settings; settings = candidate; settingsError = nil
            if !candidate.enabled || candidate.provider != old.provider { chat.newChat() }
            if !candidate.enabled { scanID = UUID(); indexing = false; applications = []; lastScan = nil; addonSession.clear(); tab = "search" }
            settingsChanged?()
            return true
        } catch { settingsError = "Could not save Loki Launch settings: \(error.localizedDescription)"; return false }
    }
    func setShortcut(_ value: LaunchShortcut) -> Bool {
        if let requestShortcut { return requestShortcut(value) }
        return change { $0.shortcut = value }
    }
    @discardableResult
    func openConversation(_ id: UUID) -> Bool {
        guard !chat.replying, let conversation = chat.conversations.first(where: { $0.id == id }) else { return false }
        if settings.provider != conversation.provider && !change({ $0.provider = conversation.provider }) { return false }
        guard chat.openConversation(id) else { return false }
        tab = "chat"
        return true
    }
    func refreshApplications(force: Bool = false) {
        guard settings.enabled, !indexing, force || lastScan == nil || Date().timeIntervalSince(lastScan!) > 60 else { return }
        indexing = true
        let id = UUID(); scanID = id
        DispatchQueue.global(qos: .userInitiated).async {
            let entries = Self.scanApplications()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.settings.enabled, self.scanID == id else { return }
                self.applications = entries; self.indexing = false; self.lastScan = Date()
            }
        }
    }
    nonisolated static func scanApplications() -> [LaunchEntry] {
        var entries: [LaunchEntry] = []
        var seen = Set<String>()
        // Safari's Applications symlink is hidden; index its system mount directly too.
        for root in ["/Applications", "/System/Applications", "/System/Cryptexes/App/System/Applications",
                     "/System/Library/CoreServices/Applications", NSHomeDirectory() + "/Applications"] {
            guard let files = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in files where url.pathExtension.lowercased() == "app" {
                files.skipDescendants()
                guard seen.insert(url.resolvingSymlinksInPath().path).inserted else { continue }
                let bundle = Bundle(url: url)
                let title = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                    bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
                entries.append(LaunchEntry(id: "app:" + url.path, title: title, subtitle: "Application · " + url.deletingLastPathComponent().path,
                    keywords: (bundle?.bundleIdentifier ?? "") + " " + url.deletingPathExtension().lastPathComponent,
                    symbol: "app", action: .application(url)))
            }
        }
        return entries
    }
    func activate(_ entry: LaunchEntry) {
        guard settings.enabled else { return }
        if entry.action == .chat { tab = "chat"; return }
        if case let .addon(packageID, commandID) = entry.action {
            guard let package = addons.package(packageID), let command = package.manifest.commands.first(where: { $0.id == commandID }) else { return }
            addonSession.open(package: package, command: command); tab = "addon"; return
        }
        perform?(entry.action)
    }
}

private final class LaunchPanel: NSPanel {
    var handleKeyEvent: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if handleKeyEvent?(event) == true { return }
        super.sendEvent(event)
    }
}

@MainActor
final class LauncherController: NSObject, NSWindowDelegate {
    private let model: LauncherModel
    private var panel: LaunchPanel?
    private var hotKey: EventHotKeyRef?
    private var registeredShortcut: LaunchShortcut?
    private var clickMonitor: Any?
    private var previousApp: NSRunningApplication?
    var beforeOpen: (() -> Void)?
    var isVisible: Bool { panel?.isVisible == true }
    var shortcutRegistered: Bool { hotKey != nil && registeredShortcut == model.settings.shortcut }

    init(model: LauncherModel) {
        self.model = model
        super.init()
        model.settingsChanged = { [weak self] in self?.configure() }
        model.requestShortcut = { [weak self] value in self?.setShortcut(value) ?? false }
        model.openPanel = { [weak self] in self?.show() }
        configure()
    }
    func configure() {
        guard model.settings.enabled else {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = nil; registeredShortcut = nil; model.shortcutError = nil
            close(); return
        }
        if registeredShortcut != model.settings.shortcut {
            let shortcut = model.settings.shortcut
            if let error = LauncherHotKey.conflict(shortcut) { model.shortcutError = error; return }
            var candidate: EventHotKeyRef?
            let result = LauncherHotKey.register(shortcut, reference: &candidate)
            guard result == noErr else { model.shortcutError = LauncherHotKey.unavailable(shortcut); return }
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = candidate; registeredShortcut = shortcut; model.shortcutError = nil
        }
    }
    private func setShortcut(_ value: LaunchShortcut) -> Bool {
        if let error = LauncherHotKey.conflict(value) { model.shortcutError = error; return false }
        if registeredShortcut == value { model.shortcutError = nil; return model.change { $0.shortcut = value } }
        guard model.settings.enabled else { return model.change { $0.shortcut = value } }
        var candidate: EventHotKeyRef?
        guard LauncherHotKey.register(value, reference: &candidate) == noErr else {
            model.shortcutError = LauncherHotKey.unavailable(value); return false
        }
        // Reserve the replacement before saving; a rejected shortcut must leave the working one intact.
        let previous = hotKey, previousShortcut = registeredShortcut
        hotKey = candidate; registeredShortcut = value
        if model.change({ $0.shortcut = value }) {
            if let previous { UnregisterEventHotKey(previous) }
            model.shortcutError = nil
            return true
        }
        if let candidate { UnregisterEventHotKey(candidate) }
        hotKey = previous; registeredShortcut = previousShortcut
        return false
    }
    func toggle() { if panel?.isVisible == true { close(restoreFocus: true) } else { show() } }
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        if model.settings.enabled && LauncherHotKey.matches(event, shortcut: model.settings.shortcut) {
            if !event.isARepeat { close(restoreFocus: true) }
            return true
        }
        guard event.keyCode == UInt16(kVK_Tab),
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              model.tab == "search" || model.tab == "chat" else { return false }
        if !event.isARepeat { model.tab = model.tab == "search" ? "chat" : "search" }
        return true
    }
    func show() {
        guard model.settings.enabled else { return }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        beforeOpen?()
        if panel == nil {
            let panel = LaunchPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 510),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isFloatingPanel = true; panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false; panel.isMovableByWindowBackground = true
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
            panel.title = "Loki Launch"; panel.delegate = self
            // Nonactivating panels can receive shortcut keystrokes directly, before text input.
            panel.handleKeyEvent = { [weak self] in self?.handleKeyEvent($0) ?? false }
            panel.contentView = NSHostingView(rootView: LauncherView(model: model, chat: model.chat, close: { [weak self] in self?.close(restoreFocus: true) }))
            self.panel = panel
        }
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let width = min(680, frame.width - 32), height = min(510, frame.height - 32)
            panel?.setFrame(NSRect(x: frame.midX - width / 2, y: frame.minY + (frame.height - height) * 0.65, width: width, height: height), display: true)
        }
        model.launchError = nil; model.refreshApplications()
        panel?.makeKeyAndOrderFront(nil)
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
        }
        NotificationCenter.default.post(name: .lokiFocusLauncher, object: nil)
    }
    func close(restoreFocus: Bool = false) {
        let wasVisible = panel?.isVisible == true
        panel?.orderOut(nil)
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }; clickMonitor = nil
        if restoreFocus && wasVisible { previousApp?.activate(options: []) }
    }
    func windowDidResignKey(_ notification: Notification) { close() }
    func shutdown() {
        close(); model.chat.stop(); model.addonSession.stop()
        if let hotKey { UnregisterEventHotKey(hotKey) }; hotKey = nil
    }
}

extension Notification.Name { static let lokiFocusLauncher = Notification.Name("LokiFocusLauncher") }
