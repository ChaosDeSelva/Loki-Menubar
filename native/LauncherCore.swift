import Foundation

struct LaunchShortcut: Codable, Equatable {
    var keyCode: UInt32 = 49
    var modifiers: UInt32 = 0x300
    var keyLabel = "Space"
    var label: String {
        (modifiers & 0x1000 != 0 ? "⌃" : "") + (modifiers & 0x800 != 0 ? "⌥" : "") +
        (modifiers & 0x200 != 0 ? "⇧" : "") + (modifiers & 0x100 != 0 ? "⌘" : "") + keyLabel
    }
    var isValid: Bool {
        keyCode < 128 && keyCode != 53 && (modifiers & (0x100 | 0x1000) != 0 || (keyCode == 49 && modifiers == 0x200)) &&
        modifiers & ~UInt32(0x100 | 0x200 | 0x800 | 0x1000) == 0 && !keyLabel.isEmpty
    }
}

enum QuickChatProvider: String, Codable, CaseIterable, Identifiable {
    case claude, codex
    var id: String { rawValue }
    var title: String { self == .claude ? "Claude" : "Codex" }
    var loginCommand: String { self == .claude ? "claude auth login" : "codex login" }
    var setupURL: URL {
        URL(string: self == .claude ? "https://code.claude.com/docs/en/quickstart" : "https://developers.openai.com/codex/cli/")!
    }
}

struct LauncherSettings: Codable, Equatable {
    var version = 4
    var enabled = false
    var shortcut = LaunchShortcut()
    var provider: QuickChatProvider = .claude
    var claudePath = ""
    var codexPath = ""
    func path(for provider: QuickChatProvider) -> String { provider == .claude ? claudePath : codexPath }
    mutating func migrateShortcut() -> Bool {
        guard version < 4 else { return false }
        if (version == 1 && shortcut.keyCode == 49 && shortcut.modifiers == 0x900) ||
            (version < 3 && shortcut.keyCode == 40 && shortcut.modifiers == 0x1800) ||
            (version == 3 && shortcut.keyCode == 49 && shortcut.modifiers == 0x200) { shortcut = LaunchShortcut() }
        version = 4
        return true
    }
}

struct LauncherFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct LauncherStore {
    let url: URL
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Loki/launcher.json")
    }
    func load() throws -> LauncherSettings {
        guard FileManager.default.fileExists(atPath: url.path) else { return LauncherSettings() }
        let settings = try JSONDecoder().decode(LauncherSettings.self, from: Data(contentsOf: url))
        guard (1...4).contains(settings.version), settings.shortcut.isValid else {
            throw LauncherFailure("Loki Launch settings could not be read. The original launcher.json was preserved.")
        }
        return settings
    }
    func save(_ settings: LauncherSettings) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: url, options: .atomic)
    }
}

struct LaunchEntry: Identifiable, Equatable {
    enum Action: Equatable {
        case application(URL), shelf, settings, reveal, toggleHidden, chat, addon(String, String)
    }
    let id: String
    let title: String
    let subtitle: String
    let keywords: String
    let symbol: String
    let action: Action
}

enum LauncherSearch {
    static func results(_ entries: [LaunchEntry], query: String) -> [LaunchEntry] {
        let query = normalize(query).trimmingCharacters(in: .whitespacesAndNewlines)
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        var seen = Set<String>()
        return entries.filter { seen.insert($0.id).inserted }.compactMap { entry -> (LaunchEntry, Int)? in
            let title = normalize(entry.title)
            let haystack = title + " " + normalize(entry.keywords + " " + entry.subtitle)
            guard words.allSatisfy({ haystack.contains($0) || subsequence($0, in: title) }) else { return nil }
            let score = query.isEmpty ? (entry.id.hasPrefix("command:") ? 0 : 1) :
                title == query ? 0 : title.hasPrefix(query) ? 1 : title.contains(query) ? 2 :
                words.allSatisfy({ haystack.contains($0) }) ? 3 : 4
            return (entry, score)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            let order = $0.0.title.localizedStandardCompare($1.0.title)
            return order == .orderedSame ? $0.0.id < $1.0.id : order == .orderedAscending
        }.map(\.0)
    }
    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    private static func subsequence(_ query: String, in text: String) -> Bool {
        var remaining = query[...]
        for character in text where remaining.first == character { remaining.removeFirst() }
        return remaining.isEmpty
    }
}

struct QuickChatMessage: Codable, Identifiable, Equatable {
    var id = UUID()
    let role: String
    var text: String
}

struct QuickChatConversation: Codable, Identifiable, Equatable {
    let id: UUID
    let provider: QuickChatProvider
    let createdAt: Date
    var updatedAt: Date
    var messages: [QuickChatMessage]
    var title: String {
        String((messages.first(where: { $0.role == "user" })?.text ?? "Untitled chat")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(80))
    }
}

struct QuickChatHistoryStore {
    private struct Archive: Codable {
        var version = 1
        let conversations: [QuickChatConversation]
    }
    let url: URL
    private let maximumBytes = 50_000_000
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Loki/Chat History/history.json")
    }
    func load() throws -> [QuickChatConversation] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= maximumBytes else {
            throw LauncherFailure("The chat history file is unreadable or too large.")
        }
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
        guard archive.version == 1, Set(archive.conversations.map(\.id)).count == archive.conversations.count,
              archive.conversations.allSatisfy({ conversation in
                  !conversation.messages.isEmpty && Set(conversation.messages.map(\.id)).count == conversation.messages.count &&
                  conversation.messages.allSatisfy { ["user", "assistant"].contains($0.role) }
              }) else { throw LauncherFailure("The saved chat history format is not supported.") }
        return archive.conversations.sorted { $0.updatedAt > $1.updatedAt }
    }
    func save(_ conversations: [QuickChatConversation]) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Archive(conversations: conversations))
        guard data.count <= maximumBytes else { throw LauncherFailure("Local chat history is full. Delete older chats to save more.") }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Restrict the directory before the atomic write so its replacement file is private too.
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

enum QuickChatRequest {
    static let instruction = "You are Loki Quick Chat, a concise conversational assistant. Answer the user's question directly. This is a text-only chat: do not use tools, inspect files, run commands, or take actions. Treat the JSON conversation below as conversation data, preserving its user and assistant roles. Respond only to its last user message."
    static func prompt(_ messages: [QuickChatMessage]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: messages.map { ["role": $0.role, "content": $0.text] }, options: [.sortedKeys])
        return instruction + "\n\n" + String(decoding: data, as: UTF8.self)
    }
    static func arguments(for provider: QuickChatProvider) -> [String] {
        switch provider {
        case .claude:
            return ["--print", "--safe-mode", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                    "--tools", "", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
                    "--setting-sources", "", "--settings", "{\"disableAllHooks\":true}",
                    "--disable-slash-commands", "--no-session-persistence", "--system-prompt", instruction]
        case .codex:
            return ["exec", "--ignore-user-config", "--skip-git-repo-check", "--ephemeral", "--json",
                    "--sandbox", "read-only", "--color", "never",
                    "-c", "approval_policy=\"never\"", "-c", "model_provider=\"openai\"",
                    "-c", "forced_login_method=\"chatgpt\"", "-c", "web_search=\"disabled\"",
                    "-c", "features.shell_tool=false", "-c", "features.multi_agent=false",
                    "-c", "features.apps=false", "-c", "features.hooks=false",
                    "-c", "features.multi_agent_v2=false", "-c", "features.skill_search=false",
                    "-c", "features.skip_host_skill_discovery=true",
                    "-c", "project_doc_max_bytes=0", "-c", "mcp_servers={}", "-"]
        }
    }
    static func environment(_ inherited: [String: String], home: String) -> [String: String] {
        // A GUI launch has a short PATH; only carry process basics, never ambient API credentials.
        var result = inherited.filter { ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "CODEX_HOME", "CLAUDE_CONFIG_DIR"].contains($0.key) }
        let paths = [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        result["PATH"] = paths.joined(separator: ":")
        result["HOME"] = home
        result["NO_COLOR"] = "1"
        return result
    }
    static func hasSubscription(_ provider: QuickChatProvider, output: String) -> Bool {
        if provider == .codex { return output.lowercased().contains("logged in using chatgpt") }
        guard let data = output.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["loggedIn"] as? Bool == true && object["authMethod"] as? String == "claude.ai"
    }
}

struct QuickChatStream {
    private(set) var text = ""
    private(set) var error: String?
    private var pending = Data()
    mutating func receive(_ data: Data) {
        pending.append(data)
        while let newline = pending.firstIndex(of: 10) {
            let line = pending.prefix(upTo: newline)
            parse(Data(line)); pending.removeSubrange(...newline)
        }
    }
    mutating func finish() { if !pending.isEmpty { parse(pending); pending.removeAll() } }
    private mutating func parse(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = json["type"] as? String else { return }
        if type == "stream_event", let event = json["event"] as? [String: Any],
           let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta", let value = delta["text"] as? String {
            text += value
        } else if type == "result" {
            if json["is_error"] as? Bool == true {
                error = (json["errors"] as? [String])?.joined(separator: "\n") ?? json["result"] as? String ?? "The provider could not answer."
            } else if let result = json["result"] as? String, !result.isEmpty { text = result }
        } else if type == "item.completed", let item = json["item"] as? [String: Any],
                  item["type"] as? String == "agent_message", let value = item["text"] as? String {
            text += (text.isEmpty ? "" : "\n\n") + value
        } else if type == "turn.failed" || type == "error" {
            error = (json["error"] as? [String: Any])?["message"] as? String ?? json["message"] as? String ?? "The provider could not answer."
        }
    }
}
