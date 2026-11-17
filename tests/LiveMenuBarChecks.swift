import AppKit
import ApplicationServices

// Manual hardware checks only. This does not replace Loki or write its preferences.
@main
struct LiveMenuBarChecks {
    enum Failure: Error { case check(String) }

    static func fail(_ message: String) throws -> Never { throw Failure.check(message) }

    static func command(_ value: String) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/Applications/Loki.app/Contents/MacOS/Loki")
        process.arguments = [value]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { try fail("Installed Loki command failed: \(value)") }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    static func rawFrame(_ element: AXUIElement) -> CGRect? {
        guard let pv = MenuDiscovery.attribute(element, kAXPositionAttribute),
              let sv = MenuDiscovery.attribute(element, kAXSizeAttribute),
              CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(pv, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(sv, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    static func divider() -> CGRect? {
        guard let loki = NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.ChaosDeSelva.Loki")
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) else { return nil }
        let root = AXUIElementCreateApplication(loki.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.3)
        guard let extra = MenuDiscovery.attribute(root, kAXExtrasMenuBarAttribute),
              CFGetTypeID(extra) == AXUIElementGetTypeID() else { return nil }
        return MenuDiscovery.children(unsafeBitCast(extra, to: AXUIElement.self))
            .first { MenuDiscovery.string($0, kAXDescriptionAttribute) == "Loki hidden icons" }.flatMap(rawFrame)
    }

    static func lookup(_ id: String) async throws -> ShelfItem {
        let items = await Task.detached { MenuDiscovery.scan().items }.value
        guard let item = items.first(where: { $0.id == id }), item.element != nil else {
            try fail("Target not discovered: \(id)")
        }
        return item
    }

    @MainActor
    static func position(_ id: String) async throws -> (ShelfItem, CGRect, CGRect) {
        let item = try await lookup(id)
        guard let frame = item.element.flatMap(MenuDiscovery.frame), let line = divider() else {
            try fail("Could not read target and divider geometry")
        }
        print("\(item.title): \(frame), divider: \(line)")
        return (item, frame, line)
    }

    @MainActor
    static func move(_ id: String, hidden: Bool) async throws {
        for attempt in 0..<2 {
            _ = try command("--reveal-all")
            try await Task.sleep(nanoseconds: 600_000_000)
            let (item, frame, line) = try await position(id)
            let window = MenuBarArranger.statusWindow(for: frame, owner: item.pid)
            print("attempt=\(attempt) destination=\(hidden ? "hidden" : "visible") window=\(String(describing: window))")
            let pointer = CGEvent(source: nil)?.location
            let targetWindow = MenuBarArranger.statusWindow(for: line, owner: 0)
            let delivered = await MenuBarArranger.commandDrag(from: CGPoint(x: frame.midX, y: frame.midY),
                to: MenuBarSections.dropPoint(divider: line, toHidden: hidden, attempt: attempt), window: window,
                destination: targetWindow, receiver: item.pid)
            guard delivered else { try fail("No complete targeted drag was dispatched; source or divider window is missing, or the drag was cancelled") }
            if let pointer, let after = CGEvent(source: nil)?.location {
                guard abs(after.x - pointer.x) < 1.01 && abs(after.y - pointer.y) < 1.01 else {
                    print("CURSOR changed: \(pointer) -> \(after)")
                    try fail("The cursor moved during the drag test; it was not warped back")
                }
                print("PASS: cursor stayed in place during targeted drag")
            }
            try await Task.sleep(nanoseconds: 500_000_000)
            _ = try command("--toggle-hidden")
            try await Task.sleep(nanoseconds: 600_000_000)
            let (_, after, collapsed) = try await position(id)
            guard collapsed.width > 1000 else { try fail("Loki did not collapse; cannot verify sides") }
            let onHiddenSide = after.midX < collapsed.minX
            if onHiddenSide == hidden {
                if !hidden {
                    guard let current = MenuBarArranger.statusWindow(for: after, owner: item.pid),
                          let rows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
                          rows.contains(where: { $0[kCGWindowNumber as String] as? CGWindowID == current.id }) else {
                        try fail("Target is on the visible side but its status window is not on screen")
                    }
                }
                print("PASS: actual target is \(hidden ? "hidden" : "visible")")
                return
            }
        }
        try fail("Target did not reach the requested side")
    }

    @MainActor
    static func main() async {
        _ = NSApplication.shared
        if let flag = CommandLine.arguments.firstIndex(of: "--log"), CommandLine.arguments.indices.contains(flag + 1) {
            let path = CommandLine.arguments[flag + 1]
            guard freopen(path, "w", stdout) != nil else { exit(2) }
            _ = freopen(path, "a", stderr)
            setbuf(stdout, nil)
        }
        guard MenuDiscovery.trusted, CGPreflightPostEventAccess() else {
            fputs("SKIP: this harness has no existing Accessibility/event access. No permission was requested and no input was posted.\n", stderr)
            exit(77)
        }
        do {
            guard let id = CommandLine.arguments.dropFirst().first else {
                try fail("Usage: LiveMenuBarChecks menu-slot:<bundle>:<slot> [--round-trip]")
            }
            guard MenuBarSections.owner(ofItem: id) == "local.topterm.app" else {
                try fail("This live check is scoped to TopTerm only")
            }
            _ = try await position(id)
            if CommandLine.arguments.contains("--recover-only") {
                try await move(id, hidden: false)
                return
            }
            guard CommandLine.arguments.contains("--round-trip") else { return }
            let initial = try command("--status")
            guard initial["arranging"] as? Bool == false, initial["backend"] as? String == "divider" else {
                try fail("Installed Loki must be idle and using the divider backend")
            }
            do {
                try await move(id, hidden: false)
                try await move(id, hidden: true)
                try await move(id, hidden: false)
                let item = try await lookup(id)
                func hasVisibleWindow() -> Bool {
                    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
                    return windows.contains { row in
                        guard row[kCGWindowOwnerPID as String] as? pid_t == item.pid,
                              let b = row[kCGWindowBounds as String] as? NSDictionary,
                              let r = CGRect(dictionaryRepresentation: b) else { return false }
                        return r.height > 80 && r.width > 80
                    }
                }
                if hasVisibleWindow() {
                    let error = await Task.detached { MenuDiscovery.activate(item) }.value
                    guard error == nil else { try fail(error!) }
                    try await Task.sleep(nanoseconds: 500_000_000)
                    guard !hasVisibleWindow() else { try fail("Could not establish a hidden TopTerm window for the opening test") }
                }
                let error = await Task.detached { MenuDiscovery.activate(item) }.value
                guard error == nil else { try fail(error!) }
                try await Task.sleep(nanoseconds: 500_000_000)
                guard hasVisibleWindow() else { try fail("Press returned, but no target app window appeared") }
                print("PASS: target window opened through the production shelf activation path")
            } catch {
                _ = try? command("--reveal-all")
                throw error
            }
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }
}
