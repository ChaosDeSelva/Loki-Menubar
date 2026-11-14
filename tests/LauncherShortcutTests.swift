import AppKit
import Carbon
import SwiftUI

@main struct LauncherShortcutTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let crossProcessShortcut = LaunchShortcut(keyCode: 64, modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey), keyLabel: "F17")
        if CommandLine.arguments.contains("--hold-test-shortcut") {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(crossProcessShortcut.keyCode, crossProcessShortcut.modifiers,
                EventHotKeyID(signature: 0x54455354, id: 1), GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &reference)
            print(status == noErr ? "READY" : "ERROR"); fflush(stdout)
            _ = readLine()
            if let reference { UnregisterEventHotKey(reference) }
            return
        }
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            guard condition() else { fatalError(name) }
            print("PASS: \(name)")
        }
        let legacy = LaunchShortcut(keyCode: 49, modifiers: UInt32(cmdKey | optionKey), keyLabel: "Space")
        if let conflict = LauncherHotKey.conflict(legacy) {
            check("macOS Finder search shortcut is rejected", conflict.contains("Finder search"))
        } else { print("SKIP: Finder search is disabled or remapped on this Mac") }
        check("New default is not a macOS symbolic shortcut", LauncherHotKey.conflict(LaunchShortcut()) == nil)
        let safari = URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications/Safari.app")
        if FileManager.default.fileExists(atPath: safari.path) {
            let applications = LauncherModel.scanApplications()
            check("Safari is searchable despite its hidden Applications link", applications.contains { entry in
                if case let .application(url) = entry.action { return url.resolvingSymlinksInPath() == safari.resolvingSymlinksInPath() }
                return false
            })
            let paths = applications.compactMap { entry -> String? in
                if case let .application(url) = entry.action { return url.resolvingSymlinksInPath().path }
                return nil
            }
            check("Application links do not duplicate search results", Set(paths).count == paths.count)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("loki-shortcut-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LauncherStore(url: root.appendingPathComponent("launcher.json"))
        let model = LauncherModel(store: store)
        let controller = LauncherController(model: model)
        defer { controller.shutdown() }
        func key(_ code: UInt16 = 48, modifiers: NSEvent.ModifierFlags = [], repeating: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: 0, context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: repeating, keyCode: code)!
        }
        model.query = "Safari"; model.chat.draft = "An unfinished question"
        check("Shift-Command-Space matches even with Caps Lock", LauncherHotKey.matches(key(49, modifiers: [.shift, .command, .capsLock]), shortcut: LaunchShortcut()))
        check("Plain Space remains available for typing", !LauncherHotKey.matches(key(49), shortcut: LaunchShortcut()))
        check("Shift-Space remains available for typing", !LauncherHotKey.matches(key(49, modifiers: [.shift]), shortcut: LaunchShortcut()))
        check("Extra modifiers do not activate the shortcut", !LauncherHotKey.matches(key(49, modifiers: [.shift, .command, .option]), shortcut: LaunchShortcut()))
        check("Tab switches Search to Quick Chat", controller.handleKeyEvent(key()) && model.tab == "chat")
        check("Held Tab does not cycle repeatedly", controller.handleKeyEvent(key(repeating: true)) && model.tab == "chat")
        check("Tab switches Quick Chat back to Search", controller.handleKeyEvent(key()) && model.tab == "search")
        check("Tab keeps the query and unsent draft", model.query == "Safari" && model.chat.draft == "An unfinished question")
        check("Modified Tab retains normal keyboard behavior", [NSEvent.ModifierFlags.shift, .command, .option, .control].allSatisfy { !controller.handleKeyEvent(key(modifiers: $0)) } && model.tab == "search")
        check("Other keys do not switch tabs", !controller.handleKeyEvent(key(49)))
        model.tab = "addon"
        check("Add-on fields retain normal Tab navigation", !controller.handleKeyEvent(key()) && model.tab == "addon")
        model.tab = "search"
        let historyLauncherStore = LauncherStore(url: root.appendingPathComponent("history-case/launcher.json"))
        let historyStore = QuickChatHistoryStore(url: historyLauncherStore.url.deletingLastPathComponent().appendingPathComponent("Chat History/history.json"))
        let savedChat = QuickChatConversation(id: UUID(), provider: .codex, createdAt: Date(), updatedAt: Date(),
            messages: [QuickChatMessage(role: "user", text: "A Codex question"), QuickChatMessage(role: "assistant", text: "A Codex answer")])
        try historyStore.save([savedChat])
        let historyModel = LauncherModel(store: historyLauncherStore)
        check("Opening history restores the conversation's provider", historyModel.openConversation(savedChat.id) && historyModel.settings.provider == .codex && historyModel.chat.messages == savedChat.messages && historyModel.tab == "chat")
        historyModel.change { $0.provider = .claude }
        check("Switching providers keeps previous chats in history", historyModel.chat.messages.isEmpty && historyModel.chat.conversations.count == 1)
        let old = LaunchShortcut(keyCode: 80, modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey), keyLabel: "F19")
        check("Disabled add-on can save a custom shortcut", model.setShortcut(old))
        model.change { $0.enabled = true }
        check("Enabled add-on registers its shortcut", model.shortcutError == nil)
        let helper = Process(), helperInput = Pipe(), helperOutput = Pipe()
        helper.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); helper.arguments = ["--hold-test-shortcut"]
        helper.standardInput = helperInput; helper.standardOutput = helperOutput
        try helper.run()
        defer { try? helperInput.fileHandleForWriting.close(); if helper.isRunning { helper.terminate() } }
        let timeout = DispatchWorkItem { if helper.isRunning { helper.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
        let ready = helperOutput.fileHandleForReading.readData(ofLength: 6)
        timeout.cancel()
        check("Another process reserves its own shortcut", String(decoding: ready, as: UTF8.self) == "READY\n")
        check("Another app's exclusive hotkey is rejected", !model.setShortcut(crossProcessShortcut) && model.settings.shortcut == old && controller.shortcutRegistered)
        try helperInput.fileHandleForWriting.close(); helper.waitUntilExit()
        let shelf = LaunchShortcut(keyCode: 37, modifiers: UInt32(controlKey | optionKey), keyLabel: "L")
        check("Conflicts cannot replace a working shortcut", !model.setShortcut(shelf) && model.settings.shortcut == old)
        let afterConflict = try store.load()
        check("Rejected shortcut cannot overwrite saved configuration", afterConflict.shortcut == old)
        let replacement = LaunchShortcut(keyCode: 90, modifiers: old.modifiers, keyLabel: "F20")
        check("Changing the registered shortcut saves and activates it", model.setShortcut(replacement) && model.settings.shortcut == replacement && model.shortcutError == nil)
        var probe: EventHotKeyRef?
        check("Old shortcut is released after successful remap", LauncherHotKey.register(old, reference: &probe) == noErr)
        if let probe { UnregisterEventHotKey(probe) }
        let occupied = LaunchShortcut(keyCode: 79, modifiers: old.modifiers, keyLabel: "F18")
        probe = nil
        check("Competing hotkey can be reserved for the conflict test", LauncherHotKey.register(occupied, reference: &probe) == noErr)
        check("A macOS registration failure preserves the current shortcut", !model.setShortcut(occupied) && model.settings.shortcut == replacement && controller.shortcutRegistered)
        if let probe { UnregisterEventHotKey(probe) }
        let backup = root.appendingPathComponent("launcher-backup.json")
        try FileManager.default.moveItem(at: store.url, to: backup)
        try FileManager.default.createDirectory(at: store.url, withIntermediateDirectories: false)
        check("A disk write failure rolls back shortcut registration", !model.setShortcut(old) && model.settings.shortcut == replacement && controller.shortcutRegistered)
        probe = nil
        check("Failed save releases its temporary replacement hotkey", LauncherHotKey.register(old, reference: &probe) == noErr)
        if let probe { UnregisterEventHotKey(probe) }
        try FileManager.default.removeItem(at: store.url)
        try FileManager.default.moveItem(at: backup, to: store.url)
        let afterFailedSave = try store.load()
        check("Failed save preserves the previous saved shortcut", afterFailedSave.shortcut == replacement)
        model.change { $0.enabled = false }
        probe = nil
        check("Disabling releases the replacement shortcut", LauncherHotKey.register(replacement, reference: &probe) == noErr)
        if let probe { UnregisterEventHotKey(probe) }
    }
}

// Registration tests never open a panel; avoid linking the rest of the application's views.
struct LauncherView: View {
    let model: LauncherModel
    let chat: QuickChatModel
    let close: () -> Void
    var body: some View { EmptyView() }
}
