import AppKit
import SwiftUI
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    var model: AppModel!
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private var shelfController: NSHostingController<AnyView>?
    private var mainWindow: NSWindow?
    private var commandObserver: NSObjectProtocol?
    private var dismissalMonitors: [Any] = []
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One owner of the shortcut and status item; reopening an existing install is harmless.
        let copies = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "io.github.ChaosDeSelva.Loki")
        if let existing = copies.first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [.activateAllWindows]); NSApp.terminate(nil); return
        }
        model = AppModel()
        model.summon = { [weak self] in self?.toggleShelf() }
        model.dismissShelf = { [weak self] in
            self?.closeShelf()
            self?.mainWindow?.orderOut(nil)
        }
        setupMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: 30)
        statusItem.autosaveName = "LokiSummon"
        if let button = statusItem.button {
            let renderer = ImageRenderer(content: LokiMark(color: .black, monochrome: true).frame(width: 18, height: 20))
            renderer.scale = 2
            let image = renderer.nsImage
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Loki · Control Option L"
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Loki")
        }
        model.visibility.configure(anchor: statusItem)
        popover.delegate = self
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        configureShelf(size: NSSize(width: 480, height: 620))
        installShortcut()
        commandObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("LokiCommand"), object: Bundle.main.bundleIdentifier, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
            guard let self, let command = notification.userInfo?["command"] as? String else { return }
            switch command {
            case "--reveal-all": self.model.visibility.stop()
            case "--shelf": self.toggleShelf()
            case "--settings": self.openSettings()
            case "--status":
                guard let request = notification.userInfo?["request"] as? String else { return }
                DistributedNotificationCenter.default().postNotificationName(Notification.Name("LokiStatus"), object: request,
                    userInfo: ["managing": self.model.visibility.managing, "concealed": self.model.visibility.concealed,
                               "message": self.model.visibility.failure ?? "", "shelfOpen": self.popover.isShown], deliverImmediately: true)
            default: break
            }
            }
        }
        // Launch quietly, including ServiceManagement login launches.
        // Reopening or clicking the status item explicitly summons the shelf.
    }

    private func setupMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let menu = NSMenu(title: "Loki")
        menu.addItem(withTitle: "About Loki", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(withTitle: "Open Loki", action: #selector(openMain), keyEquivalent: "0")
        menu.addItem(withTitle: "Summon Shelf", action: #selector(summonShelf), keyEquivalent: "")
        menu.addItem(withTitle: "Reveal All Menu Bar Items", action: #selector(revealAll), keyEquivalent: "")
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkUpdates), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Loki", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(withTitle: "Quit Loki", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = menu
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc private func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Loki", action: #selector(openMain), keyEquivalent: "")
            menu.addItem(withTitle: "Reveal All Menu Bar Items", action: #selector(revealAll), keyEquivalent: "")
            menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Loki", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            for item in menu.items { item.target = item.action == #selector(NSApplication.terminate(_:)) ? NSApp : self }
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else { toggleShelf() }
    }

    func toggleShelf() {
        model.visibility.reveal()
        if popover.isShown { closeShelf(); return }
        guard let button = statusItem.button, button.window != nil else { return }
        mainWindow?.orderOut(nil)
        let available = button.window?.screen?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        configureShelf(size: NSSize(width: min(480, available.width - 24), height: min(620, available.height - 32)))
        model.query = ""
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        installDismissalMonitors()
        NotificationCenter.default.post(name: .lokiFocusSearch, object: nil)
    }

    func closeShelf() {
        popover.performClose(nil)
        removeDismissalMonitors()
    }

    func popoverDidClose(_ notification: Notification) { removeDismissalMonitors() }

    private func removeDismissalMonitors() {
        dismissalMonitors.forEach(NSEvent.removeMonitor)
        dismissalMonitors.removeAll()
    }

    private func installDismissalMonitors() {
        removeDismissalMonitors()
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.closeShelf()
        }) { dismissalMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if event.type == .keyDown && event.keyCode == 53 && event.window === self.popover.contentViewController?.view.window {
                self.closeShelf(); return nil
            }
            if event.type != .keyDown, event.window === self.mainWindow {
                self.closeShelf()
            }
            return event
        }) { dismissalMonitors.append(monitor) }
    }

    private func configureShelf(size: NSSize) {
        // A popover asks its hosting view for its ideal size. Constrain the ROOT,
        // otherwise LazyVStack's ideal height can expand the whole popover off-screen.
        let root = AnyView(ShelfView(model: model, compact: true).frame(width: size.width, height: size.height))
        if let shelfController { shelfController.rootView = root }
        else {
            let controller = NSHostingController(rootView: root)
            shelfController = controller
            popover.contentViewController = controller
        }
        shelfController?.preferredContentSize = size
        popover.contentSize = size
    }

    func hideWindows() { closeShelf(); mainWindow?.orderOut(nil); NSApp.hide(nil) }

    func showMainWindow() {
        closeShelf()
        if mainWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 710),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Loki"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = NSColor(red: 0.055, green: 0.075, blue: 0.065, alpha: 1)
            window.contentView = NSHostingView(rootView: MainView(model: model).padding(.top, 22).background(LokiStyle.background))
            window.minSize = NSSize(width: 840, height: 662)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("LokiMainWindow")
            if !window.setFrameUsingName("LokiMainWindow") { window.center() }
            mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
        model.refresh()
    }
    @objc private func openMain() { showMainWindow() }
    @objc private func summonShelf() { toggleShelf() }
    @objc private func revealAll() { model.visibility.stop() }
    @objc private func openSettings() { model.page = "settings"; showMainWindow() }
    @objc private func checkUpdates() { model.updater.checkForUpdates() }
    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Loki", .applicationVersion: "0.1.0", .credits: NSAttributedString(string: "A little order. A little mischief.\nA native, local menu utility for your Mac.")])
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { toggleShelf(); return false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func installShortcut() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.toggleShelf() }
            return noErr
        }, 1, &eventType, nil, &eventHandler)
        let id = EventHotKeyID(signature: 0x4c4f4b49, id: 1)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
        model.shortcutRegistered = result == noErr
    }
    func applicationWillTerminate(_ notification: Notification) {
        model?.visibility.stop()
        removeDismissalMonitors()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

let app = NSApplication.shared
let commands = ["--reveal-all", "--shelf", "--settings", "--status"]
if let command = CommandLine.arguments.first(where: { commands.contains($0) }) {
    let bundle = Bundle.main.bundleIdentifier ?? "io.github.ChaosDeSelva.Loki"
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if !running { fputs("Loki is not running. Open the installed app first.\n", stderr); exit(1) }
    let request = UUID().uuidString
    var received = false
    let observer = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("LokiStatus"), object: request, queue: .main) { notification in
        if let info = notification.userInfo, let data = try? JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]) { print(String(decoding: data, as: UTF8.self)) }
        received = true
    }
    DistributedNotificationCenter.default().postNotificationName(Notification.Name("LokiCommand"), object: bundle,
        userInfo: ["command": command, "request": request], deliverImmediately: true)
    if command == "--status" {
        let deadline = Date().addingTimeInterval(2)
        while !received && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    }
    DistributedNotificationCenter.default().removeObserver(observer)
    if command == "--status" && !received { fputs("Loki did not respond.\n", stderr); exit(2) }
} else if CommandLine.arguments.contains("--diagnose") {
    let result = MenuDiscovery.trusted ? MenuDiscovery.scan() : DiscoveryResult(items: [], scanned: 0, unresponsive: 0)
    let report: [String: Any] = ["version": "0.1.0", "os": ProcessInfo.processInfo.operatingSystemVersionString,
        "accessibility": MenuDiscovery.trusted, "menuItemCount": result.items.count, "scannedProcesses": result.scanned,
        "runningAppCount": MenuDiscovery.appShortcuts().count, "screenCapture": false, "systemHiding": false]
    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
        print(String(decoding: data, as: UTF8.self))
    }
} else {
    MainActor.assumeIsolated {
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
