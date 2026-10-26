import AppKit

/// Owns the hidden section. One checklist, two mechanisms:
/// - macOS 14–26: a public divider status item left of Loki's rune. Chosen icons are
///   Command-dragged left of it, and widening it pushes them off-screen.
/// - macOS 27: macOS keeps every status item on screen, so widening cannot hide anything
///   (measured on 27.0.1). The only working mechanism is Apple's undocumented allowlist,
///   which hides whole apps. It is resolved at runtime and turns itself off if absent.
/// Neither state is persisted: quitting or a crash always leaves every icon visible.
@MainActor
final class VisibilityController: NSObject, ObservableObject {
    enum Backend: String { case divider, allowlist, unavailable }

    @Published private(set) var mode = MenuBarSections.Mode.idle
    @Published private(set) var failure: String?
    @Published private(set) var summary: String?
    let backend: Backend = {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 else { return .divider }
        return MenuBarVisibility.available ? .allowlist : .unavailable
    }()
    var concealed: Bool { mode == .collapsed }
    var arranging: Bool { mode == .arranging }
    var usesAllowlist: Bool { backend == .allowlist }
    private(set) var hidden = Set<String>()
    private(set) var paused = false
    private let allowlist = MenuBarVisibility()
    private var allowlistRequest = 0
    private var divider: NSStatusItem?
    private weak var anchor: NSStatusItem?
    private var timer: Timer?
    private var notifications: [NSObjectProtocol] = []
    private var lastInteraction = Date()
    private var delay: TimeInterval = 3
    private var autoRehide = true
    private var hoverReveal = false
    private var revealRequested = false
    /// An allowlist hide macOS has not confirmed yet. While set, nothing re-requests it:
    /// each new request invalidates the previous one, so repeating it could starve the hide.
    private var allowlistPending = false
    private var refreshWork: DispatchWorkItem?
    /// macOS 27 only: icons are shown because a microphone or camera is in use.
    @Published private(set) var privacyHold = false
    private var captureCheck = 0

    func configure(anchor: NSStatusItem, hidden: Set<String>, delay: TimeInterval, autoRehide: Bool, hoverReveal: Bool) {
        self.anchor = anchor
        // Choices saved on another macOS version may name icons this backend cannot hide.
        self.hidden = hidden.filter { MenuBarSections.hideable($0, allowlist: backend == .allowlist) }
        if backend == .divider {
            // Created after the rune, so a fresh install places the divider immediately to its left.
            let item = NSStatusBar.system.statusItem(withLength: 0)
            item.autosaveName = "LokiDivider"
            if let button = item.button {
                button.target = self
                button.action = #selector(dividerClicked)
                button.setAccessibilityLabel("Loki hidden icons")
                button.toolTip = "Hide icons again"
            }
            divider = item
        }
        settings(delay: delay, autoRehide: autoRehide, hoverReveal: hoverReveal)
        guard backend != .unavailable, !self.hidden.isEmpty else { return }
        // The previous session's choices still apply; tuck them away once the bar settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.mode == .idle, !self.hidden.isEmpty else { return }
            self.setMode(.revealed)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard self.mode == .revealed, !self.revealRequested else { return }
                self.collapse()
            }
        }
    }

    func settings(delay: TimeInterval, autoRehide: Bool, hoverReveal: Bool) {
        self.delay = max(1, min(30, delay))
        self.autoRehide = autoRehide
        self.hoverReveal = hoverReveal
        updateTimer()
    }

    /// Makes the hidden section match `hidden` exactly, then tucks it away.
    func apply(_ chosen: Set<String>) {
        guard mode != .arranging else { return }
        let hidden = chosen.filter { MenuBarSections.hideable($0, allowlist: usesAllowlist) }
        self.hidden = hidden
        setFailure(nil)
        revealRequested = false
        paused = false
        switch backend {
        case .unavailable:
            setFailure("This macOS build does not expose a way to hide menu-bar icons. Every icon stays visible.")
        case .allowlist:
            let apps = Set(hidden.compactMap(MenuBarSections.owner(ofItem:))).count
            summary = hidden.isEmpty ? nil : "\(apps) app\(apps == 1 ? "" : "s") hidden"
            // Leaving .collapsed or a pending hide invalidates the old allowlist before the new one.
            setMode(hidden.isEmpty ? .idle : .revealed)
            collapse()
        case .divider:
            guard MenuDiscovery.trusted else { setFailure("Allow Accessibility so Loki can move icons for you."); return }
            setMode(.arranging)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                let outcome = await MenuBarArranger.arrange(hidden: hidden, divider: { [weak self] in self?.dividerFrame })
                setMode(.revealed)
                let waiting = outcome.missing.isEmpty ? "" : " · \(outcome.missing.count) not running"
                summary = "\(hidden.count) chosen · \(outcome.moved) moved\(waiting)"
                // An icon that should stay visible but could not leave the hidden side would vanish on collapse.
                let stranded = outcome.failed.filter { !hidden.contains($0) }
                if !outcome.failed.isEmpty {
                    setFailure("\(outcome.failed.count) icon\(outcome.failed.count == 1 ? "" : "s") could not be moved. That app may not allow it; try Command-dragging it yourself.")
                }
                if hidden.isEmpty { setMode(.idle) }
                else if revealRequested || !stranded.isEmpty { pause() }
                else { collapse() }
            }
        }
    }

    func reveal() {
        guard mode == .collapsed || allowlistPending else { return }
        setMode(.revealed)
        lastInteraction = Date()
    }

    func collapse() {
        guard mode == .revealed, !hidden.isEmpty, backend != .unavailable else {
            if mode == .revealed && hidden.isEmpty { setMode(.idle) }
            return
        }
        paused = false
        revealRequested = false
        if privacyHold && CaptureActivity.inUse { return }
        privacyHold = false
        switch backend {
        case .divider:
            guard orderingValid else {
                setFailure("Loki’s divider is not left of its rune. Choose Apply to let Loki reset it.")
                pause(); return
            }
            setMode(.collapsed)
        case .allowlist:
            guard Self.installedInApplications else {
                setFailure("Move Loki to your Applications folder first. On macOS 27, hiding also hides apps macOS does not track, and a copy outside Applications would hide Loki’s own icon.")
                pause(); return
            }
            if !allowlistPending { hideWithAllowlist() }
        case .unavailable: break
        }
    }

    func toggle() { if mode == .collapsed { reveal() } else { collapse() } }

    /// Recovery: show everything and stop rehiding until the person asks again.
    func revealAll() {
        revealRequested = true
        if mode == .collapsed || allowlistPending { setMode(.revealed) }
        pause()
    }

    var orderingValid: Bool {
        guard let divider = Self.frame(of: divider), let anchor = Self.frame(of: anchor) else { return false }
        return MenuBarSections.orderingValid(divider: divider, anchor: anchor)
    }

    /// The allowlist is asynchronous. The mode changes only when macOS confirms; a request
    /// replaced or cancelled in the meantime is ignored. Also refreshes a live hide, when
    /// called while collapsed, so newly launched apps join the allowlist.
    private func hideWithAllowlist() {
        allowlistRequest += 1
        allowlistPending = true
        let request = allowlistRequest
        allowlist.hide(hidden) { [weak self] error in
            MainActor.assumeIsolated {
                guard let self, self.allowlistRequest == request, self.allowlistPending else { return }
                self.allowlistPending = false
                if let error {
                    if self.mode == .collapsed { self.setMode(.revealed) }
                    self.setFailure(error); self.pause()
                } else if self.mode == .revealed { self.setMode(.collapsed) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.allowlistRequest == request, self.allowlistPending else { return }
            self.cancelAllowlist()
            if self.mode == .collapsed { self.setMode(.revealed) }
            self.setFailure("macOS did not confirm hiding. Every icon is visible.")
            self.pause()
        }
    }

    private func cancelAllowlist() {
        allowlistRequest += 1
        allowlistPending = false
        allowlist.reveal()
    }

    /// The allowlist shrinks the system's recording indicators to a dot, so show every icon
    /// while capture is active and tuck them away again afterwards.
    private func holdForCapture(_ inUse: Bool) {
        if inUse && mode == .collapsed {
            setMode(.revealed)
            privacyHold = true
            pause()
            summary = "Showing every icon while your microphone or camera is in use"
        } else if !inUse && privacyHold {
            privacyHold = false
            summary = nil
            if !revealRequested && mode == .revealed { collapse() } else { updateTimer() }
        }
    }

    private func pause() {
        paused = true
        updateTimer()
    }

    @objc private func dividerClicked() { collapse() }

    private func setFailure(_ message: String?) {
        if failure != message { failure = message }
    }

    private func setMode(_ new: MenuBarSections.Mode) {
        if backend == .allowlist && new != .collapsed && (mode == .collapsed || allowlistPending) {
            cancelAllowlist()
        }
        mode = new
        if let divider {
            divider.length = MenuBarSections.dividerLength(new)
            let image = new == .revealed || new == .arranging ? NSImage(systemSymbolName: "chevron.compact.left", accessibilityDescription: "Hide icons") : nil
            image?.isTemplate = true
            divider.button?.image = image
        }
        updateTimer()
    }

    /// Runs only while it has something to watch: a revealed section to rehide, or hover to detect.
    private func updateTimer() {
        let needed = (mode == .revealed && autoRehide && !paused) || (mode == .collapsed && hoverReveal)
            || (backend == .allowlist && (mode == .collapsed || privacyHold))
        if needed, timer == nil {
            let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !needed {
            timer?.invalidate(); timer = nil
        }
    }

    private func tick() {
        if backend == .allowlist && (mode == .collapsed || privacyHold) {
            captureCheck += 1
            if captureCheck % 3 == 0 { holdForCapture(CaptureActivity.inUse) }
            if privacyHold { return }
        }
        let inBar = Self.pointerInMenuBar
        if mode == .collapsed {
            if hoverReveal && inBar { reveal() }
            return
        }
        guard mode == .revealed else { return }
        let menuOpen = Self.menuIsOpen
        let mouseDown = NSEvent.pressedMouseButtons != 0
        let command = NSEvent.modifierFlags.contains(.command)
        if inBar || menuOpen || mouseDown || command { lastInteraction = Date() }
        if MenuBarSections.shouldRehide(pointerInBar: inBar, menuOpen: menuOpen, mouseDown: mouseDown, commandHeld: command,
                                        idle: Date().timeIntervalSince(lastInteraction), delay: delay) { collapse() }
    }

    private var dividerFrame: CGRect? {
        Self.frame(of: divider).map { MenuBarSections.flipped($0, primaryHeight: MenuBarArranger.primaryHeight) }
    }

    /// AppKit (bottom-left origin) frame; only compare it with other frames from this function.
    private static func frame(of item: NSStatusItem?) -> CGRect? {
        guard let button = item?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// A menu or popover hanging from the menu bar. Floating panels elsewhere on screen don't count.
    private static var menuIsOpen: Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return true }
        let tops = NSScreen.screens.map { MenuBarSections.flipped($0.frame, primaryHeight: MenuBarArranger.primaryHeight).minY }
        return windows.contains { info in
            guard (info[kCGWindowLayer as String] as? Int ?? 0) >= Int(CGWindowLevelForKey(.popUpMenuWindow)),
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
            return rect.width > 40 && rect.height > 40 && tops.contains { abs(rect.minY - $0) < 48 }
        }
    }

    /// Measured on macOS 27.0.1: the allowlist kept Loki's icon only for a copy in /Applications.
    /// A build-folder copy, signed or not, disappeared along with the apps it was asked to hide.
    static var installedInApplications: Bool {
        let path = Bundle.main.bundleURL.deletingLastPathComponent().path
        return path == "/Applications" || path.hasSuffix("/Applications") || path.hasPrefix("/Applications/")
    }

    /// The real menu-bar band of each display, not a generous guess.
    static var pointerInMenuBar: Bool {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            let inset = screen.frame.maxY - screen.visibleFrame.maxY
            let height = inset > 0 ? inset : NSStatusBar.system.thickness
            return NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height).contains(point)
        }
    }

    override init() {
        super.init()
        // A new display arrangement can strand the divider: hold everything visible while it
        // settles, then hide again only if the layout is still sound.
        notifications.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.backend == .divider, self.mode == .collapsed else { return }
                self.setMode(.revealed)
                self.pause()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    guard self.mode == .revealed, !self.revealRequested else { return }
                    if self.orderingValid { self.collapse() } else { self.setFailure("The display layout changed. Choose Apply to tuck icons away again.") }
                }
            }
        })
        // The allowlist names running apps. A newly launched app must stay visible, so refresh
        // the allowlist instead of revealing everything.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            notifications.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.backend == .allowlist else { return }
                    // Coalesce bursts, such as login, into one refresh.
                    self.refreshWork?.cancel()
                    let work = DispatchWorkItem { [weak self] in
                        guard let self, self.mode == .collapsed || self.allowlistPending else { return }
                        self.hideWithAllowlist()
                    }
                    self.refreshWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
                }
            })
        }
    }

    /// Called from applicationWillTerminate; macOS also drops both mechanisms when the process exits.
    func restoreForQuit() {
        timer?.invalidate(); timer = nil
        refreshWork?.cancel()
        cancelAllowlist()
        divider?.length = MenuBarSections.shownWidth
    }
}
