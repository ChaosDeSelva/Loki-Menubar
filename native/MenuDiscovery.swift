import AppKit
import ApplicationServices

enum ItemKind: String { case menu, app }

struct ShelfItem: Identifiable {
    let id: String
    let title: String
    let appName: String
    let bundleID: String
    let pid: pid_t
    let icon: NSImage?
    let element: AXUIElement?
    let kind: ItemKind
    var record: ShelfRecord { ShelfRecord(id: id, title: title, app: appName) }
}

struct DiscoveryResult {
    var items: [ShelfItem]
    var scanned: Int
    var unresponsive: Int
}

enum MenuDiscovery {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ key: String) -> String {
        (attribute(element, key) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    static func appShortcuts() -> [ShelfItem] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier && !$0.isTerminated
        }.compactMap { app in
            guard let bundle = app.bundleIdentifier, let name = app.localizedName else { return nil }
            return ShelfItem(id: "app:\(bundle)", title: name, appName: "Running application", bundleID: bundle,
                             pid: app.processIdentifier, icon: app.icon, element: nil, kind: .app)
        }
    }

    /// Read only menu extras, never the application's File/Edit menus or document content.
    static func scan() -> DiscoveryResult {
        guard trusted else { return DiscoveryResult(items: [], scanned: 0, unresponsive: 0) }
        let apps = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
            ($0.activationPolicy != .prohibited || $0.bundleIdentifier == "com.apple.MenuBarAgent" || $0.bundleIdentifier == "com.apple.controlcenter")
        }.sorted { ($0.bundleIdentifier == "com.apple.MenuBarAgent" ? 0 : 1) < ($1.bundleIdentifier == "com.apple.MenuBarAgent" ? 0 : 1) }
        var items: [ShelfItem] = []
        var scanned = 0
        var unresponsive = 0
        var seen = Set<String>()
        let deadline = Date().addingTimeInterval(5)
        for app in apps {
            guard Date() < deadline else { break }
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.08)
            let name = app.localizedName ?? "Utility"
            let bundle = app.bundleIdentifier ?? "process.\(name)"
            let isAgent = name == "MenuBarAgent" || bundle.localizedCaseInsensitiveContains("menubaragent")
            var roots: [AXUIElement] = []
            var extra: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(root, kAXExtrasMenuBarAttribute as CFString, &extra)
            scanned += 1
            if result == .cannotComplete { unresponsive += 1; continue }
            if let extra, CFGetTypeID(extra) == AXUIElementGetTypeID() { roots.append(unsafeBitCast(extra, to: AXUIElement.self)) }
            // Only AXExtrasMenuBar is allowed here. AXMenuBar and arbitrary
            // agent windows include the Apple/File/Edit menus, not status items.
            var queue = roots.map { ($0, 0) }
            var visited = Set<CFHashCode>()
            var occurrences: [String: Int] = [:]
            var count = 0
            while !queue.isEmpty && count < 250 && Date() < deadline {
                let (element, depth) = queue.removeFirst()
                guard visited.insert(CFHash(element)).inserted else { continue }
                count += 1
                let role = string(element, kAXRoleAttribute)
                if role == kAXMenuBarItemRole || (isAgent && role == kAXButtonRole && depth > 0) {
                    let identifier = string(element, kAXIdentifierAttribute)
                    let title = [string(element, kAXDescriptionAttribute), string(element, kAXTitleAttribute), string(element, kAXHelpAttribute)]
                        .first(where: { !$0.isEmpty }) ?? name
                    guard title != "Loki", title != "Apple", title != "Apple menu", title != "",
                          !identifier.contains(Bundle.main.bundleIdentifier ?? "io.github.ChaosDeSelva.Loki") else { continue }
                    let identity = identifier.isEmpty ? title : identifier
                    let base = "menu:\(bundle):\(identity)"
                    let occurrence = occurrences[base, default: 0]
                    occurrences[base] = occurrence + 1
                    // System controls are mirrored across displays but represent
                    // one logical item. Never suffix those duplicate discoveries.
                    let id = isAgent || occurrence == 0 ? base : "\(base):\(occurrence)"
                    if seen.insert(id).inserted {
                        items.append(ShelfItem(id: id, title: String(title.prefix(100)), appName: isAgent ? "Menu bar" : name,
                            bundleID: bundle, pid: app.processIdentifier, icon: isAgent ? nil : app.icon,
                            element: element, kind: .menu))
                    }
                } else if depth < 4 {
                    queue.append(contentsOf: children(element).map { ($0, depth + 1) })
                }
            }
        }
        return DiscoveryResult(items: items, scanned: scanned, unresponsive: unresponsive)
    }

    static func activate(_ item: ShelfItem) -> String? {
        guard let owner = NSRunningApplication(processIdentifier: item.pid), !owner.isTerminated,
              owner.bundleIdentifier == item.bundleID else { return "The menu owner has quit. Refresh the shelf." }
        if item.kind == .app {
            guard let app = NSRunningApplication(processIdentifier: item.pid), !app.isTerminated,
                  app.bundleIdentifier == item.bundleID else { return "This app has quit. Refresh the shelf to update it." }
            return app.activate(options: [.activateAllWindows]) ? nil : "macOS could not bring this app forward."
        }
        guard trusted else { return "Allow Accessibility in System Settings, then try again." }
        guard let element = item.element else { return "This item is no longer available. Refresh the shelf." }
        AXUIElementSetMessagingTimeout(element, 0.3)
        // Avoid remote AX actions remaining pending during menu tracking.
        // Use the same down/up sequence as a real click,
        // and only for a freshly resolved menu-extra rectangle on a screen edge.
        guard let positionValue = attribute(element, kAXPositionAttribute),
              let sizeValue = attribute(element, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return "This item has no clickable position. Open it directly from the menu bar."
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size),
              size.width > 0, size.width < 500, size.height > 0, size.height < 80 else {
            return "This menu item is no longer visible. Reveal it and refresh."
        }
        let rectangle = CGRect(origin: position, size: size)
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else { return "No active display." }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success,
              MenuGeometry.isSafe(rectangle, on: displays.prefix(Int(displayCount)).map(CGDisplayBounds)) else { return "This item is outside the visible menu bar. Reveal it and refresh." }
        let point = CGPoint(x: rectangle.midX, y: rectangle.midY)
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            return "macOS could not create the menu click."
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return nil
    }
}
