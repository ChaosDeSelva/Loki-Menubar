import AppKit

/// Owns the hidden section. One checklist, two mechanisms:
/// - macOS 14–26: a public divider status item left of Loki's rune. Chosen icons are
///   Command-dragged left of it, and widening it pushes them off-screen.
/// - macOS 27: macOS keeps every status item on screen, so widening cannot hide anything
///   (measured on 27.0.1). The only working mechanism is Apple's undocumented allowlist,
///   which hides whole apps. It is resolved at runtime and turns itself off if absent.
/// Neither state is persisted: quitting or a crash always leaves every icon visible.
/// The macOS 27 mechanism, behind a seam so the controller's bookkeeping can be tested
/// without touching the real menu bar. `MenuBarVisibility` is the production conformance.
protocol MenuBarAllowlist: AnyObject {
    func hide(_ items: Set<String>, completion: @escaping (String?) -> Void)
    func reveal()
}
extension MenuBarVisibility: MenuBarAllowlist {}

@MainActor
final class VisibilityController: NSObject, ObservableObject {
    enum Backend: String { case divider, allowlist, unavailable }

    nonisolated static var systemBackend: Backend {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 else { return .divider }
        return MenuBarVisibility.available ? .allowlist : .unavailable
    }

    @Published private(set) var mode = MenuBarSections.Mode.idle
    @Published private(set) var failure: String?
    @Published private(set) var summary: String?
    let backend: Backend
    var concealed: Bool { mode == .collapsed }
    var arranging: Bool { mode == .arranging }
    var usesAllowlist: Bool { backend == .allowlist }
    private(set) var hidden = Set<String>()
    private(set) var paused = false
    private(set) var lastArrangementDiagnostics: [String] = []
    private let allowlist: MenuBarAllowlist
    private let captureInUse: () -> Bool
    private let installed: () -> Bool
    private let confirmationTimeout: TimeInterval
    private let trusted: () -> Bool
    private let arrange: (Set<String>, @escaping () -> CGRect?, @escaping (Bool) -> Void) async -> MenuBarArranger.Outcome
    private let unexpectedHiddenItems: (Set<String>, @escaping () -> CGRect?) async -> Bool
    private let interactionActive: @MainActor () -> Bool
    private let validOrdering: (() -> Bool)?
    private var reconciliationTask: Task<Void, Never>?
    private var layoutRevision = 0
    private var dividerCheck = 0
    private var arrangementTask: Task<Void, Never>?
    private var queuedChoice: Set<String>?
    private var stopped = false
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
    private(set) var allowlistPending = false
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.restoreSavedSelection(self.hidden)
        }
    }

    func restoreSavedSelection(_ chosen: Set<String>) {
        guard !stopped, mode == .idle, !chosen.isEmpty, !revealRequested else { return }
        // Icons may have launched while Loki was closed; saved positions are not saved choices.
        apply(chosen)
    }

    func settings(delay: TimeInterval, autoRehide: Bool, hoverReveal: Bool) {
        self.delay = max(1, min(30, delay))
        self.autoRehide = autoRehide
        self.hoverReveal = hoverReveal
        updateTimer()
    }

    /// Makes the hidden section match `hidden` exactly, then tucks it away.
    func apply(_ chosen: Set<String>) {
        guard !stopped else { return }
        if mode == .arranging { queuedChoice = chosen; revealRequested = false; return }
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
            guard trusted() else { setFailure("Allow Accessibility so Loki can move icons for you."); return }
            setMode(.arranging)
            arrangementTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled, !stopped else { return }
                let outcome = await arrange(hidden, { [weak self] in self?.dividerFrame },
                    { [weak self] collapsed in
                        guard let self, !self.stopped else { return }
                        self.divider?.length = MenuBarSections.dividerLength(collapsed ? .collapsed : .arranging)
                    })
                guard !Task.isCancelled, !stopped else { return }
                arrangementTask = nil
                lastArrangementDiagnostics = outcome.diagnostics
                setMode(.revealed)
                if let next = queuedChoice {
                    queuedChoice = nil
                    let keepVisible = revealRequested
                    apply(next)
                    if keepVisible { revealAll() }
                    return
                }
                let waiting = outcome.missing.isEmpty ? "" : " · \(outcome.missing.count) not running"
                summary = "\(hidden.count) chosen · \(outcome.moved) moved\(waiting)"
                // An icon that should stay visible but could not leave the hidden side would vanish on collapse.
                let stranded = outcome.failed.filter { !hidden.contains($0) }
                if !outcome.failed.isEmpty {
                    let names = ListFormatter.localizedString(byJoining: outcome.failedTitles.isEmpty ? outcome.failed : outcome.failedTitles)
                    setFailure("Loki couldn’t reposition \(names)." + (stranded.isEmpty ? "" : " Hiding is paused because an unchecked icon could not be brought back. A crowded menu bar may still leave it out of view."))
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
        guard !stopped else { return }
        guard mode == .revealed, !hidden.isEmpty, backend != .unavailable else {
            if mode == .revealed && hidden.isEmpty { setMode(.idle) }
            return
        }
        paused = false
        revealRequested = false
        if backend == .allowlist && captureInUse() { holdForCapture(true); return }
        privacyHold = false
        switch backend {
        case .divider:
            guard orderingValid else {
                setFailure("Loki’s divider is not left of its rune. Choose Apply to let Loki reset it.")
                pause(); return
            }
            setMode(.collapsed)
        case .allowlist:
            guard installed() else {
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
        if let validOrdering { return validOrdering() }
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
                if self.captureInUse() { self.holdForCapture(true); return }
                self.allowlistPending = false
                if let error {
                    if self.mode == .collapsed { self.setMode(.revealed) }
                    self.setFailure(error); self.pause()
                } else if self.mode == .revealed { self.setMode(.collapsed) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + confirmationTimeout) { [weak self] in
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
    func checkCapture() { holdForCapture(captureInUse()) }

    private func holdForCapture(_ inUse: Bool) {
        guard backend == .allowlist, !stopped else { return }
        if inUse && (mode == .collapsed || allowlistPending || (mode == .revealed && !hidden.isEmpty)) {
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
        layoutRevision += 1
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

    /// Collapsed dividers also need polling: apps can add icons without a workspace launch event.
    private func updateTimer() {
        let needed = (mode == .revealed && autoRehide && !paused) || (mode == .collapsed && hoverReveal)
            || (backend == .divider && mode == .collapsed)
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
        if backend == .divider && mode == .collapsed {
            dividerCheck += 1
            if dividerCheck % 5 == 0 { refreshDivider() }
        }
        if backend == .allowlist && (mode == .collapsed || privacyHold) {
            captureCheck += 1
            if captureCheck % 3 == 0 { checkCapture() }
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
    nonisolated static var installedInApplications: Bool {
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

    init(backend: Backend = VisibilityController.systemBackend, allowlist: MenuBarAllowlist = MenuBarVisibility(),
         captureInUse: @escaping () -> Bool = { CaptureActivity.inUse },
         installed: @escaping () -> Bool = { VisibilityController.installedInApplications },
         confirmationTimeout: TimeInterval = 5,
         trusted: @escaping () -> Bool = { MenuDiscovery.trusted },
         validOrdering: (() -> Bool)? = nil,
         interactionActive: @escaping @MainActor () -> Bool = {
             VisibilityController.pointerInMenuBar || VisibilityController.menuIsOpen ||
                 NSEvent.pressedMouseButtons != 0 || NSEvent.modifierFlags.contains(.command)
         },
         unexpectedHiddenItems: @escaping (Set<String>, @escaping () -> CGRect?) async -> Bool = { hidden, divider in
             await MenuBarArranger.hasUnexpectedHiddenItems(hidden: hidden, divider: divider)
         },
         arrange: @escaping (Set<String>, @escaping () -> CGRect?, @escaping (Bool) -> Void) async -> MenuBarArranger.Outcome = { hidden, divider, collapse in
             await MenuBarArranger.arrange(hidden: hidden, divider: divider, collapse: collapse)
         }) {
        self.backend = backend
        self.allowlist = allowlist
        self.captureInUse = captureInUse
        self.installed = installed
        self.confirmationTimeout = confirmationTimeout
        self.trusted = trusted
        self.arrange = arrange
        self.validOrdering = validOrdering
        self.interactionActive = interactionActive
        self.unexpectedHiddenItems = unexpectedHiddenItems
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
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            notifications.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // Coalesce bursts, such as login, into one refresh.
                    self.refreshWork?.cancel()
                    let work = DispatchWorkItem { [weak self] in
                        guard let self else { return }
                        if self.backend == .divider { self.refreshDivider() }
                        else { self.refreshAllowlist() }
                    }
                    self.refreshWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
                }
            })
        }
    }

    func refreshDivider() {
        guard !stopped, backend == .divider, mode == .collapsed, !paused,
              reconciliationTask == nil, trusted(), !interactionActive() else { return }
        let revision = layoutRevision
        let choice = hidden
        reconciliationTask = Task { @MainActor in
            let misplaced = await unexpectedHiddenItems(choice, { [weak self] in self?.dividerFrame })
            reconciliationTask = nil
            guard !Task.isCancelled, !stopped, layoutRevision == revision else { return }
            guard misplaced, !interactionActive() else { return }
            apply(choice)
        }
    }

    /// Re-issues a live or pending hide so apps launched since then are allowed.
    func refreshAllowlist() {
        guard !stopped, backend == .allowlist, mode == .collapsed || allowlistPending else { return }
        if captureInUse() { holdForCapture(true); return }
        hideWithAllowlist()
    }

    /// Called from applicationWillTerminate; macOS also drops both mechanisms when the process exits.
    func restoreForQuit() {
        stopped = true
        reconciliationTask?.cancel(); reconciliationTask = nil
        queuedChoice = nil
        arrangementTask?.cancel(); arrangementTask = nil
        timer?.invalidate(); timer = nil
        refreshWork?.cancel()
        cancelAllowlist()
        divider?.length = MenuBarSections.shownWidth
    }
}
