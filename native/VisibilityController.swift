import AppKit

/// Uses an ordinary status-item spacer; no private frameworks or assessment mode.
/// Only the icons the user places to the left of the divider are tucked away.
final class VisibilityController: NSObject, ObservableObject {
    @Published private(set) var concealed = false
    @Published private(set) var managing = false
    @Published private(set) var failure: String?
    var supported: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27 }
    private var divider: NSStatusItem?
    private weak var anchor: NSStatusItem?
    private var timer: Timer?
    private var notifications: [NSObjectProtocol] = []
    private var lastInteraction = Date()
    private var delay: TimeInterval = 3
    private var autoRehide = true
    private var awaitingFirstHide = false

    func configure(anchor: NSStatusItem) { self.anchor = anchor }

    func start(delay: TimeInterval, autoRehide: Bool) {
        stop()
        guard supported else {
            failure = "Icon hiding is unavailable on macOS 27 in this build. Use macOS Menu Bar settings to choose which controls appear."
            return
        }
        self.delay = max(1, min(30, delay))
        self.autoRehide = autoRehide
        failure = nil
        let item = NSStatusBar.system.statusItem(withLength: 22)
        item.autosaveName = "LokiDivider"
        item.isVisible = true
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: "Loki divider")
            button.image?.isTemplate = true
            button.toolTip = "Loki divider · Command-drag icons to its left to tuck them away. Click to reveal."
            button.setAccessibilityLabel("Loki divider")
            button.target = self
            button.action = #selector(dividerClicked)
        }
        divider = item
        managing = true
        // First start is setup-only: the user must explicitly choose Tuck icons.
        lastInteraction = Date()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func tuck() {
        guard managing else { return }
        failure = nil
        awaitingFirstHide = true
        lastInteraction = Date()
    }

    @objc private func dividerClicked() {
        if concealed { reveal() } else { tuck() }
    }

    private func tick() {
        guard managing else { return }
        if Self.pointerNearMenuBar || NSApp.isActive || NSEvent.pressedMouseButtons != 0 ||
            NSEvent.modifierFlags.contains(.command) || Self.popupIsVisible {
            if concealed { reveal() }
            lastInteraction = Date()
            return
        }
        guard Date().timeIntervalSince(lastInteraction) >= delay,
              !concealed, awaitingFirstHide else { return }
        guard let anchorFrame = Self.frame(of: anchor),
              let dividerFrame = Self.frame(of: divider),
              dividerFrame.midX < anchorFrame.midX else {
            failure = "Command-drag the divider to the left of Loki’s icon, then try Tuck icons again."
            awaitingFirstHide = false
            return
        }
        divider?.length = 10000
        concealed = true
        if !autoRehide { awaitingFirstHide = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.concealed else { return }
            guard let frame = Self.frame(of: self.anchor),
                  NSScreen.screens.contains(where: { $0.frame.intersects(frame) && frame.width > 0 }) else {
                self.reveal(); self.awaitingFirstHide = false
                self.failure = "This display layout cannot keep Loki visible. Icons have been revealed."
                return
            }
        }
    }

    private static func frame(of item: NSStatusItem?) -> CGRect? {
        guard let button = item?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private static var popupIsVisible: Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return true }
        return windows.contains { info in
            guard (info[kCGWindowLayer as String] as? Int ?? 0) >= Int(CGWindowLevelForKey(.popUpMenuWindow)),
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
            return rect.width > 40 && rect.height > 40
        }
    }

    static var pointerNearMenuBar: Bool {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.contains {
            NSRect(x: $0.frame.minX, y: $0.frame.maxY - 64, width: $0.frame.width, height: 64).contains(point)
        }
    }

    func reveal() {
        divider?.length = 22
        concealed = false
        lastInteraction = Date()
    }

    func stop() {
        reveal()
        managing = false; awaitingFirstHide = false
        timer?.invalidate(); timer = nil
        if let divider { NSStatusBar.system.removeStatusItem(divider) }
        divider = nil
    }

    override init() {
        super.init()
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            notifications.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.stop() })
        }
        notifications.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.reveal() })
        notifications.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.stop() })
    }

    deinit {
        timer?.invalidate()
        if let divider { NSStatusBar.system.removeStatusItem(divider) }
        for observer in notifications {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
