import Foundation
import Darwin

@main
struct LauncherTests {
    @MainActor static func main() async throws {
        var passed = 0
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
            passed += 1; print("PASS: \(name)"); fflush(stdout)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("loki-launcher-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LauncherStore(url: root.appendingPathComponent("launcher.json"))
        var settings = try store.load()
        check("Launcher is opt-in on a fresh install", !settings.enabled)
        check("Default shortcut is Shift-Command-Space", settings.shortcut.label == "⇧⌘Space" && settings.shortcut.isValid)
        var legacy = LauncherSettings(); legacy.version = 1
        legacy.shortcut = LaunchShortcut(keyCode: 49, modifiers: 0x900, keyLabel: "Space")
        check("Conflicting old default migrates", legacy.migrateShortcut() && legacy.shortcut == LaunchShortcut() && legacy.version == 4)
        check("Shortcut migration is idempotent", !legacy.migrateShortcut())
        legacy.version = 2; legacy.shortcut = LaunchShortcut(keyCode: 40, modifiers: 0x1800, keyLabel: "K")
        check("Control-Option-K migrates to Shift-Command-Space", legacy.migrateShortcut() && legacy.shortcut == LaunchShortcut())
        legacy.version = 3; legacy.shortcut = LaunchShortcut(keyCode: 49, modifiers: 0x200, keyLabel: "Space")
        try store.save(legacy)
        legacy = try store.load()
        check("Saved Shift-Space migrates to Shift-Command-Space", legacy.migrateShortcut() && legacy.shortcut == LaunchShortcut())
        check("Shift with typing keys remains unavailable", !LaunchShortcut(keyCode: 0, modifiers: 0x200, keyLabel: "A").isValid)
        check("Plain Space remains a typing key", !LaunchShortcut(keyCode: 49, modifiers: 0, keyLabel: "Space").isValid)
        legacy.version = 1; legacy.shortcut = LaunchShortcut(keyCode: 0, modifiers: 0x1100, keyLabel: "A")
        check("Migration preserves a custom shortcut", legacy.migrateShortcut() && legacy.shortcut.keyCode == 0 && legacy.shortcut.modifiers == 0x1100)
        check("Unmodified shortcuts rejected", !LaunchShortcut(keyCode: 0, modifiers: 0, keyLabel: "A").isValid)
        check("Escape rejected as a shortcut", !LaunchShortcut(keyCode: 53, keyLabel: "Escape").isValid)
        check("Unsupported modifier bits rejected", !LaunchShortcut(modifiers: 0x101, keyLabel: "Space").isValid)
        settings.enabled = true; settings.provider = .codex; settings.codexPath = "/opt/custom/codex"
        settings.shortcut = LaunchShortcut(keyCode: 40, modifiers: 0x1000 | 0x200, keyLabel: "K")
        try store.save(settings)
        let roundTrip = try store.load()
        check("Opt-in, custom shortcut, provider and path persist", roundTrip == settings)
        try Data("broken".utf8).write(to: store.url)
        do { _ = try store.load(); check("Corrupt settings rejected", false) } catch { check("Corrupt settings rejected", true) }
        let preserved = try String(contentsOf: store.url, encoding: .utf8)
        check("Corrupt settings preserved", preserved == "broken")
        settings.version = 99; try store.save(settings)
        do { _ = try store.load(); check("Future settings version rejected", false) } catch { check("Future settings version rejected", true) }
        settings.version = 4

        let safari = LaunchEntry(id: "app:safari", title: "Safari", subtitle: "Application", keywords: "com.apple.Safari", symbol: "app", action: .application(root))
        let studio = LaunchEntry(id: "app:studio", title: "Visual Studio Code", subtitle: "Application", keywords: "editor", symbol: "app", action: .application(root))
        let settingsEntry = LaunchEntry(id: "command:settings", title: "Loki Settings", subtitle: "Preferences", keywords: "configure shortcut", symbol: "gear", action: .settings)
        let unicode = LaunchEntry(id: "app:unicode", title: "Öresund", subtitle: "Application", keywords: "", symbol: "app", action: .application(root))
        let entries = [safari, studio, settingsEntry, unicode, safari]
        check("Search coalesces duplicate IDs", LauncherSearch.results(entries, query: "").count == 4)
        check("Commands lead empty search", LauncherSearch.results(entries, query: "").first == settingsEntry)
        check("Exact search ignores case and padding", LauncherSearch.results(entries, query: " SAFARI ") == [safari])
        check("Search matches app initials", LauncherSearch.results(entries, query: "vsc") == [studio])
        check("Search matches command aliases", LauncherSearch.results(entries, query: "shortcut") == [settingsEntry])
        check("Search handles multiple words", LauncherSearch.results(entries, query: "studio code") == [studio])
        check("Search folds diacritics", LauncherSearch.results(entries, query: "oresund") == [unicode])
        check("Unmatched search is empty", LauncherSearch.results(entries, query: "no-such-app") == [])
        let prompt = try QuickChatRequest.prompt([QuickChatMessage(role: "user", text: "$(rm -rf /)\n\"hi\""), QuickChatMessage(role: "assistant", text: "answer")])
        check("Conversation encodes roles and quotes as JSON", prompt.contains("\"role\":\"user\"") && prompt.contains("\\\"hi\\\""))
        check("Prompt never becomes a CLI argument", !QuickChatRequest.arguments(for: .codex).contains(prompt))
        let environment = QuickChatRequest.environment(["OPENAI_API_KEY": "secret", "ANTHROPIC_API_KEY": "secret", "ANTHROPIC_AUTH_TOKEN": "secret", "CLAUDE_CODE_OAUTH_TOKEN": "secret", "PATH": "/untrusted", "CODEX_HOME": "/test-codex", "HOME": "/bad"], home: "/test-home")
        check("Ambient credentials are not inherited", !environment.values.contains("secret"))
        check("GUI PATH includes CLI install paths", environment["PATH"]?.contains("/test-home/.local/bin") == true && environment["PATH"]?.contains("/opt/homebrew/bin") == true)
        check("Explicit Codex auth location preserved", environment["CODEX_HOME"] == "/test-codex" && environment["HOME"] == "/test-home")
        check("Codex subscription detected", QuickChatRequest.hasSubscription(.codex, output: "Logged in using ChatGPT\n"))
        check("Codex API key rejected", !QuickChatRequest.hasSubscription(.codex, output: "Logged in using an API key"))
        check("Claude subscription detected", QuickChatRequest.hasSubscription(.claude, output: "{\"loggedIn\":true,\"authMethod\":\"claude.ai\"}"))
        check("Claude API key rejected", !QuickChatRequest.hasSubscription(.claude, output: "{\"loggedIn\":true,\"authMethod\":\"api_key\"}"))
        check("Signed-out Claude rejected", !QuickChatRequest.hasSubscription(.claude, output: "{\"loggedIn\":false,\"authMethod\":\"claude.ai\"}"))
        var stream = QuickChatStream()
        let events = "{\"type\":\"stream_event\",\"event\":{\"delta\":{\"type\":\"text_delta\",\"text\":\"Hi 👋\"}}}\n{\"type\":\"result\",\"result\":\"Hi 👋\",\"is_error\":false}"
        for byte in events.utf8 { stream.receive(Data([byte])) }
        stream.finish()
        check("Streaming tolerates split JSON and UTF8 with no final newline", stream.text == "Hi 👋")
        check("Final Claude result does not duplicate deltas", stream.text.components(separatedBy: "Hi").count == 2)
        var codex = QuickChatStream()
        codex.receive(Data("log noise\n{\"type\":\"item.completed\",\"item\":{\"type\":\"reasoning\",\"text\":\"private\"}}\n{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"Answer\"}}\n".utf8))
        check("Only assistant output is displayed", codex.text == "Answer")
        codex.receive(Data("{\"type\":\"turn.failed\",\"error\":{\"message\":\"Rate limited\"}}\n".utf8))
        check("Provider errors are surfaced", codex.error == "Rate limited")
        var claudeError = QuickChatStream()
        claudeError.receive(Data("{\"type\":\"result\",\"is_error\":true,\"errors\":[\"Usage limit\"]}\n".utf8))
        check("Claude result errors are surfaced", claudeError.error == "Usage limit")

        func fixture(_ name: String, _ script: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try Data(("#!/bin/sh\n" + script).utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return url
        }
        let env = QuickChatRequest.environment(ProcessInfo.processInfo.environment, home: NSHomeDirectory())
        let echo = try fixture("echo", "cat\nprintf 'diagnostic' >&2\n")
        let output = try LocalProcessRunner().run(executable: echo, arguments: [], input: "a question", directory: root, environment: env)
        check("Process transports stdin and drains both streams", output.status == 0 && output.stdout == "a question" && output.stderr == "diagnostic")
        let noisy = try fixture("noisy", "head -c 200000 /dev/zero >&2\nprintf 'finished'\n")
        let noisyOutput = try LocalProcessRunner().run(executable: noisy, arguments: [], directory: root, environment: env)
        check("Large stderr cannot block stdout", noisyOutput.stdout == "finished" && noisyOutput.stderr.utf8.count == 32_768)
        let failure = try fixture("failure", "printf 'Unsupported option' >&2\nexit 2\n")
        let failureOutput = try LocalProcessRunner().run(executable: failure, arguments: [], input: String(repeating: "x", count: 100_000), directory: root, environment: env)
        check("Early CLI exit survives a broken stdin pipe", failureOutput.status == 2 && failureOutput.stderr == "Unsupported option")
        let sleepy = try fixture("sleepy", "exec /bin/sleep 10\n")
        let start = Date()
        do {
            _ = try LocalProcessRunner().run(executable: sleepy, arguments: [], directory: root, environment: env, timeout: 0.1)
            check("Timeout terminates process", false)
        } catch { check("Timeout terminates process", error.localizedDescription.contains("too long") && Date().timeIntervalSince(start) < 3) }
        let cancelled = LocalProcessRunner(); cancelled.cancel()
        do {
            _ = try cancelled.run(executable: echo, arguments: [], directory: root, environment: env)
            check("Cancellation before launch is respected", false)
        } catch { check("Cancellation before launch is respected", error.localizedDescription == "Reply stopped.") }
        let oversized = try fixture("oversized", "head -c 2100000 /dev/zero\n")
        do {
            _ = try LocalProcessRunner().run(executable: oversized, arguments: [], directory: root, environment: env)
            check("Excessive stdout is bounded", false)
        } catch { check("Excessive stdout is bounded", error.localizedDescription.contains("too large")) }
        let closedPipes = try fixture("closed-pipes", "exec 1>&- 2>&-\nexec /bin/sleep 10\n")
        let closedStart = Date()
        do {
            _ = try LocalProcessRunner().run(executable: closedPipes, arguments: [], directory: root, environment: env, timeout: 0.1)
            check("Timeout still applies after output pipes close", false)
        } catch { check("Timeout still applies after output pipes close", error.localizedDescription.contains("too long") && Date().timeIntervalSince(closedStart) < 1) }
        let daemonPID = root.appendingPathComponent("daemon.pid")
        let detachCode = "import os,time; pid=os.fork(); os._exit(0) if pid else None; os.setsid(); open('daemon.pid','w').write(str(os.getpid())); time.sleep(5)"
        let detachedStart = Date()
        do {
            defer {
                if let raw = try? String(contentsOf: daemonPID, encoding: .utf8), let pid = Int32(raw) { kill(pid, SIGKILL) }
            }
            _ = try LocalProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-c", detachCode], directory: root, environment: env, timeout: 0.5)
            check("Detached descendants cannot hold the runner open", false)
        } catch { check("Detached descendants cannot hold the runner open", error.localizedDescription.contains("too long") && Date().timeIntervalSince(detachedStart) < 2) }
        check("Missing executable detected", QuickChatExecutable.find(.codex, customPath: root.appendingPathComponent("missing").path) == nil)
        check("Custom executable detected", QuickChatExecutable.find(.codex, customPath: echo.path) == echo)

        let provider = try fixture("provider", "if [ \"$1\" = auth ]; then printf '{\"loggedIn\":true,\"authMethod\":\"claude.ai\"}'; exit 0; fi\ncat >\"$0.input\"\nprintf '{\"type\":\"result\",\"result\":\"Test answer\",\"is_error\":false}\\n'\n")
        settings.provider = .claude; settings.claudePath = provider.path
        let historyStore = QuickChatHistoryStore(url: root.appendingPathComponent("History/history.json"))
        let chat = QuickChatModel(historyStore: historyStore); chat.draft = "Hello"
        var disabled = settings; disabled.enabled = false
        chat.send(settings: disabled)
        check("Disabled add-on cannot submit a chat", !chat.replying && chat.messages.isEmpty)
        chat.send(settings: settings)
        let deadline = Date().addingTimeInterval(5)
        while chat.replying && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        check("Chat completes through subscription preflight and process", !chat.replying && chat.error == nil && chat.messages.last?.text == "Test answer")
        let firstConversationID = chat.activeConversationID!
        let firstHistory = try historyStore.load()
        check("Completed chat persists its provider, messages, and IDs", firstHistory.count == 1 && firstHistory[0].provider == .claude && firstHistory[0].messages == chat.messages)
        let permissions = try FileManager.default.attributesOfItem(atPath: historyStore.url.path)[.posixPermissions] as? NSNumber
        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: historyStore.url.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber
        check("Chat history is private to the Mac account", permissions?.intValue == 0o600 && directoryPermissions?.intValue == 0o700)
        chat.draft = "Follow up"; chat.send(settings: settings)
        while chat.replying && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        let submitted = try String(contentsOfFile: provider.path + ".input", encoding: .utf8)
        check("Chat sends follow-up context to the client", chat.messages.count == 4 && submitted.contains("Test answer") && submitted.contains("Follow up") && submitted.contains("\"role\":\"assistant\""))
        check("Follow-ups update one conversation", chat.conversations.count == 1 && chat.activeConversationID == firstConversationID && chat.conversations[0].messages.count == 4)
        chat.newChat()
        check("New Chat clears transcript and draft", chat.messages.isEmpty && chat.draft.isEmpty && chat.error == nil)
        check("New Chat retains earlier conversations in history", chat.conversations.count == 1 && chat.activeConversationID == nil)
        let restarted = QuickChatModel(historyStore: historyStore)
        check("History survives restarting without opening private content automatically", restarted.conversations.count == 1 && restarted.messages.isEmpty)
        check("Saved conversations reopen with full context", restarted.openConversation(firstConversationID) && restarted.messages.count == 4)
        restarted.newChat(); restarted.draft = "A second conversation"; restarted.send(settings: settings)
        let historyDeadline = Date().addingTimeInterval(5)
        while restarted.replying && Date() < historyDeadline { try await Task.sleep(nanoseconds: 20_000_000) }
        let secondConversationID = restarted.activeConversationID!
        check("History lists newest conversations first with question titles", restarted.conversations.count == 2 && restarted.conversations[0].id == secondConversationID && restarted.conversations[0].title == "A second conversation")
        check("Deleting an older chat preserves the active conversation", restarted.deleteConversation(firstConversationID) && restarted.activeConversationID == secondConversationID && restarted.messages.count == 2)
        let afterDelete = try historyStore.load()
        check("Deleted chats stay deleted after restart", afterDelete.count == 1 && afterDelete[0].id == secondConversationID)
        let historyBackup = historyStore.url.deletingLastPathComponent().appendingPathComponent("backup.json")
        try FileManager.default.moveItem(at: historyStore.url, to: historyBackup)
        try FileManager.default.createDirectory(at: historyStore.url, withIntermediateDirectories: false)
        check("Failed history deletion keeps the conversation visible", !restarted.deleteConversation(secondConversationID) && restarted.conversations.count == 1 && restarted.historyError != nil)
        try FileManager.default.removeItem(at: historyStore.url)
        try FileManager.default.moveItem(at: historyBackup, to: historyStore.url)
        check("Deleting the active chat clears its editor", restarted.deleteConversation(secondConversationID) && restarted.messages.isEmpty && restarted.activeConversationID == nil)
        restarted.stop()
        let emptiedHistory = try historyStore.load()
        check("Stopping cannot resurrect a deleted conversation", emptiedHistory.isEmpty)
        let corruptHistory = QuickChatHistoryStore(url: root.appendingPathComponent("corrupt-history.json"))
        try Data("unreadable history".utf8).write(to: corruptHistory.url)
        let preservedChat = QuickChatModel(historyStore: corruptHistory)
        preservedChat.draft = "Keep working"; preservedChat.send(settings: settings)
        let corruptDeadline = Date().addingTimeInterval(5)
        while preservedChat.replying && Date() < corruptDeadline { try await Task.sleep(nanoseconds: 20_000_000) }
        let originalHistory = try String(contentsOf: corruptHistory.url, encoding: .utf8)
        check("Unreadable history is preserved while new chats still work", originalHistory == "unreadable history" && preservedChat.historyError != nil && preservedChat.messages.last?.text == "Test answer")
        settings.claudePath = failure.path; chat.draft = "Retry this"
        chat.send(settings: settings)
        let errorDeadline = Date().addingTimeInterval(5)
        while chat.replying && Date() < errorDeadline { try await Task.sleep(nanoseconds: 20_000_000) }
        check("Auth failure preserves the question for retry", chat.error != nil && chat.draft == "Retry this" && chat.messages.isEmpty)
        chat.newChat(); settings.claudePath = sleepy.path; chat.draft = "Stop this"
        chat.send(settings: settings); chat.stop()
        try await Task.sleep(nanoseconds: 100_000_000)
        check("Stopping ignores stale process callbacks", !chat.replying && chat.messages.isEmpty && chat.draft == "Stop this")
        check("Stopped unanswered requests do not become empty saved chats", chat.conversations.count == 1 && chat.conversations[0].id == firstConversationID)
        let partialProvider = try fixture("partial-provider", "if [ \"$1\" = auth ]; then printf '{\"loggedIn\":true,\"authMethod\":\"claude.ai\"}'; exit 0; fi\ncat >/dev/null\nprintf '{\"type\":\"stream_event\",\"event\":{\"delta\":{\"type\":\"text_delta\",\"text\":\"Partial answer\"}}}\\n'\nexec /bin/sleep 10\n")
        let partialStore = QuickChatHistoryStore(url: root.appendingPathComponent("partial/history.json"))
        let partialChat = QuickChatModel(historyStore: partialStore)
        settings.claudePath = partialProvider.path; partialChat.draft = "Interrupt this answer"; partialChat.send(settings: settings)
        let partialDeadline = Date().addingTimeInterval(5)
        while partialChat.messages.last?.text != "Partial answer" && Date() < partialDeadline { try await Task.sleep(nanoseconds: 20_000_000) }
        check("History cannot switch or delete while a reply is running", partialChat.replying && !partialChat.openConversation(partialChat.activeConversationID!) && !partialChat.deleteConversation(partialChat.activeConversationID!))
        partialChat.stop()
        let partialHistory = try partialStore.load()
        check("Stopping saves the partial reply for later", partialHistory.count == 1 && partialHistory[0].messages.last?.text == "Partial answer" && partialHistory[0].messages.count == 2)
        let blankProvider = try fixture("blank-provider", "if [ \"$1\" = auth ]; then printf '{\"loggedIn\":true,\"authMethod\":\"claude.ai\"}'; exit 0; fi\ncat >/dev/null\nprintf '{\"type\":\"result\",\"result\":\"   \",\"is_error\":false}\\n'\n")
        partialChat.newChat(); settings.claudePath = blankProvider.path; partialChat.draft = "Retry a blank reply"; partialChat.send(settings: settings)
        let blankDeadline = Date().addingTimeInterval(5)
        while partialChat.replying && Date() < blankDeadline { try await Task.sleep(nanoseconds: 20_000_000) }
        check("Whitespace-only answers restore the draft without saving an empty chat", partialChat.draft == "Retry a blank reply" && partialChat.messages.isEmpty && partialChat.conversations.count == 1)
        print("\(passed) launcher tests passed")
    }
}
