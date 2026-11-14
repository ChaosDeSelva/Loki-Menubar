import Foundation
import Combine
import Darwin


enum QuickChatExecutable {
    static func find(_ provider: QuickChatProvider, customPath: String, home: String = NSHomeDirectory()) -> URL? {
        let paths = customPath.isEmpty ? [home + "/.local/bin/" + provider.rawValue,
            "/opt/homebrew/bin/" + provider.rawValue, "/usr/local/bin/" + provider.rawValue] : [customPath]
        return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }
}

@MainActor
final class QuickChatModel: ObservableObject {
    @Published var draft = ""
    @Published private(set) var messages: [QuickChatMessage] = []
    @Published private(set) var replying = false
    @Published private(set) var error: String?
    @Published private(set) var status = "Uses your signed-in subscription"
    @Published private(set) var conversations: [QuickChatConversation] = []
    @Published private(set) var activeConversationID: UUID?
    @Published private(set) var historyError: String?
    private var activeProvider: QuickChatProvider?
    private let historyStore: QuickChatHistoryStore
    private var canSaveHistory = true
    private var request: LocalProcessRunner?
    private var requestID = UUID()
    private var task: Task<Void, Never>?
    var canSend: Bool { !replying && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init(historyStore: QuickChatHistoryStore = QuickChatHistoryStore()) {
        self.historyStore = historyStore
        do { conversations = try historyStore.load() }
        catch {
            canSaveHistory = false
            historyError = "Chat history could not be read and was preserved. New chats will stay in memory. \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func persist(_ candidate: [QuickChatConversation]) -> Bool {
        guard canSaveHistory else { return false }
        do { try historyStore.save(candidate); historyError = nil; return true }
        catch { historyError = "Could not save chat history: \(error.localizedDescription)"; return false }
    }
    private func saveConversation() {
        guard let id = activeConversationID, let provider = activeProvider else { return }
        let savedMessages = messages.filter { !$0.text.isEmpty }
        let previous = conversations.first { $0.id == id }
        guard previous?.messages != savedMessages else {
            if historyError != nil { persist(conversations) }
            return
        }
        var candidate = conversations.filter { $0.id != id }
        if !savedMessages.isEmpty {
            candidate.insert(QuickChatConversation(id: id, provider: provider, createdAt: previous?.createdAt ?? Date(),
                updatedAt: Date(), messages: savedMessages), at: 0)
        }
        conversations = candidate
        persist(candidate)
    }
    @discardableResult
    func openConversation(_ id: UUID) -> Bool {
        guard !replying, conversations.contains(where: { $0.id == id }) else { return false }
        stop()
        guard let conversation = conversations.first(where: { $0.id == id }) else { return false }
        activeConversationID = id; activeProvider = conversation.provider
        messages = conversation.messages; draft = ""; error = nil
        return true
    }
    @discardableResult
    func deleteConversation(_ id: UUID) -> Bool {
        guard !replying, conversations.contains(where: { $0.id == id }) else { return false }
        let candidate = conversations.filter { $0.id != id }
        guard persist(candidate) else { return false }
        conversations = candidate
        if activeConversationID == id { activeConversationID = nil; activeProvider = nil; messages = []; draft = ""; error = nil }
        return true
    }

    func send(settings: LauncherSettings) {
        guard settings.enabled, canSend else { return }
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard question.count <= 16_000, messages.reduce(0, { $0 + $1.text.count }) + question.count <= 80_000 else {
            error = "This chat is full or the message is too long. Shorten your message or start a new chat."; return
        }
        let provider = settings.provider
        guard let executable = QuickChatExecutable.find(provider, customPath: settings.path(for: provider)) else {
            error = "Install \(provider.title)'s command-line client, then sign in with ‘\(provider.loginCommand)’. You can choose its location in Loki settings."; return
        }
        let user = QuickChatMessage(role: "user", text: question)
        let conversation = messages + [user]
        guard let prompt = try? QuickChatRequest.prompt(conversation) else { error = "Could not prepare this message."; return }
        if activeConversationID == nil { activeConversationID = UUID() }
        activeProvider = provider
        messages.append(user); messages.append(QuickChatMessage(role: "assistant", text: ""))
        saveConversation()
        draft = ""; error = nil; replying = true; status = "Checking \(provider.title) sign-in…"
        let id = UUID(); requestID = id
        let process = LocalProcessRunner(); request = process
        var environment = QuickChatRequest.environment(ProcessInfo.processInfo.environment, home: NSHomeDirectory())
        environment["PATH"] = executable.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "")
        task = Task { [weak self] in
            do {
                let answer = try await Task.detached(priority: .userInitiated) { () throws -> String in
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Loki-Chat-\(UUID().uuidString)")
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    defer { try? FileManager.default.removeItem(at: directory) }
                    let authArgs = provider == .claude ? ["auth", "status"] : ["login", "status"]
                    let auth = try process.run(executable: executable, arguments: authArgs, directory: directory, environment: environment, timeout: 15)
                    guard auth.status == 0, QuickChatRequest.hasSubscription(provider, output: provider == .claude ? auth.stdout : auth.stdout + auth.stderr) else {
                        throw LauncherFailure("Sign in to \(provider.title) with ‘\(provider.loginCommand)’ using your subscription, then try again. API-key sign-ins are not used for Quick Chat.")
                    }
                    await MainActor.run { [weak self] in if self?.requestID == id { self?.status = "\(provider.title) is replying…" } }
                    var stream = QuickChatStream()
                    let output = try process.run(executable: executable, arguments: QuickChatRequest.arguments(for: provider), input: prompt,
                        directory: directory, environment: environment) { data in
                        stream.receive(data)
                        let text = stream.text
                        Task { @MainActor [weak self] in self?.update(text, requestID: id) }
                    }
                    stream.finish()
                    if let error = stream.error { throw LauncherFailure(String(error.prefix(1600))) }
                    guard output.status == 0 else {
                        let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                        throw LauncherFailure("\(provider.title) exited with code \(output.status). \(String(detail.suffix(1200)))\nCheck your sign-in and usage limits, and update the CLI if it reports an unknown option.")
                    }
                    guard !stream.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw LauncherFailure("\(provider.title) returned no reply. Check your subscription and update its command-line client, then try again.")
                    }
                    return stream.text
                }.value
                guard let self, self.requestID == id else { return }
                self.update(answer, requestID: id); self.finish()
            } catch {
                guard let self, self.requestID == id else { return }
                self.error = error.localizedDescription
                self.restoreUnansweredDraft(); self.finish()
            }
        }
    }

    private func update(_ text: String, requestID: UUID) {
        guard self.requestID == requestID, replying, messages.last?.role == "assistant" else { return }
        messages[messages.count - 1].text = text
    }
    private func finish() { replying = false; request = nil; task = nil; status = "Uses your signed-in subscription"; saveConversation() }
    private func restoreUnansweredDraft() {
        if messages.last?.role == "assistant", messages.last?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            messages.removeLast()
            if messages.last?.role == "user" { draft = messages.removeLast().text }
        }
    }
    func stop() {
        requestID = UUID(); request?.cancel(); task?.cancel()
        if replying { restoreUnansweredDraft(); error = "Reply stopped." }
        finish()
    }
    func newChat() { stop(); activeConversationID = nil; activeProvider = nil; messages = []; draft = ""; error = nil }
}
