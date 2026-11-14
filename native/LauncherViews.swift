import AppKit
import SwiftUI

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var chat: QuickChatModel
    let close: () -> Void
    @State private var selection: String?
    @State private var historyQuery = ""
    @State private var deletingConversation: UUID?
    @FocusState private var focus: String?
    private let accent = Color(red: 0.76, green: 0.9, blue: 0.52)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                LokiMark(color: accent).frame(width: 20, height: 24)
                Text("LOKI LAUNCH").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(accent)
                Spacer()
                tab("Search", id: "search", key: "1")
                tab("Quick Chat", id: "chat", key: "2")
                Button(action: close) { Text("esc").font(.system(size: 10, design: .monospaced)).padding(6) }
                    .buttonStyle(.plain).foregroundStyle(LokiStyle.muted).help("Close launcher").accessibilityLabel("Close launcher")
            }.padding(.horizontal, 22).padding(.vertical, 16)
            Divider().overlay(Color.white.opacity(0.06))
            if model.tab == "chat" { chatContent }
            else if model.tab == "history" { historyContent }
            else if model.tab == "addon" {
                AddOnRunnerView(session: model.addonSession) { model.addonSession.clear(); model.tab = "search" }
            } else { searchContent }
            Divider().overlay(Color.white.opacity(0.06))
            HStack(spacing: 14) {
                if model.tab == "search" {
                    Text("↑↓  Navigate"); Text("↵  Open"); Text("Tab  Chat")
                    Spacer()
                    if model.indexing { ProgressView().controlSize(.mini); Text("Finding apps…") }
                    else { Text("\(model.applications.count) apps · local search") }
                } else if model.tab == "chat" {
                    Text(chat.replying ? chat.status : "\(model.settings.provider.title) · subscription")
                    Spacer()
                    Text("Tab  Search"); Text(chat.historyError == nil ? "Saved locally" : "History not saved")
                } else if model.tab == "history" {
                    Text("Chat history · this Mac only"); Spacer(); Text("\(chat.conversations.count) chats")
                } else {
                    Text("Local add-on"); Spacer(); Text("⌘1  Search")
                }
            }.font(.system(size: 10)).foregroundStyle(LokiStyle.muted).padding(.horizontal, 22).padding(.vertical, 12)
        }
        .background(LokiStyle.background).foregroundStyle(LokiStyle.text).preferredColorScheme(.dark)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.14)))
        .onAppear { focus = model.tab }
        .onReceive(NotificationCenter.default.publisher(for: .lokiFocusLauncher)) { _ in focus = model.tab }
        .onChange(of: model.tab) { focus = nil }
        .onExitCommand(perform: close)
    }
    private func tab(_ title: String, id: String, key: KeyEquivalent) -> some View {
        Button { model.tab = id } label: {
            Text(title).font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 7)
                .background(model.tab == id ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(model.tab == id ? accent : LokiStyle.muted)
        }.buttonStyle(.plain).keyboardShortcut(key, modifiers: .command)
    }
    private var searchContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(accent)
                TextField("Search apps and Loki commands…", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 20)).focused($focus, equals: "search")
                    .onAppear { DispatchQueue.main.async { focus = "search" } }
                    .accessibilityLabel("Search apps and commands")
                    .onSubmit { activateSelection() }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }.padding(22)
            if let error = model.launchError { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 22) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        if model.results.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "magnifyingglass").font(.system(size: 28)).foregroundStyle(LokiStyle.muted)
                                Text("No apps or commands found").font(.headline)
                                Button("Ask \(model.settings.provider.title) instead") { chat.draft = model.query; model.tab = "chat" }
                                    .buttonStyle(.plain).foregroundStyle(accent)
                            }.frame(maxWidth: .infinity).padding(.top, 42)
                        }
                        ForEach(model.results) { entry in
                            Button { model.activate(entry) } label: {
                                HStack(spacing: 13) {
                                    icon(entry).frame(width: 32, height: 32)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                        Text(entry.subtitle).font(.system(size: 10)).foregroundStyle(LokiStyle.muted).lineLimit(1)
                                    }
                                    Spacer()
                                    if entry.id == selectedEntry?.id { Image(systemName: "return").font(.system(size: 12)).foregroundStyle(accent) }
                                }.padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
                                    .background(entry.id == selectedEntry?.id ? accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).id(entry.id)
                                .accessibilityLabel("\(entry.title), \(entry.subtitle)")
                        }
                    }.padding(.horizontal, 12).padding(.bottom, 12)
                }
                .onChange(of: selection) { if let selection { proxy.scrollTo(selection, anchor: .center) } }
                .onChange(of: model.query) { selection = model.results.first?.id; if let selection { proxy.scrollTo(selection, anchor: .top) } }
            }
        }.frame(maxHeight: .infinity)
    }
    private var selectedEntry: LaunchEntry? { model.results.first(where: { $0.id == selection }) ?? model.results.first }
    private func activateSelection() { if let selectedEntry { model.activate(selectedEntry) } }
    private func move(_ offset: Int) {
        let entries = model.results
        guard !entries.isEmpty else { return }
        let index = entries.firstIndex(where: { $0.id == selectedEntry?.id }) ?? 0
        selection = entries[min(max(0, index + offset), entries.count - 1)].id
    }
    @ViewBuilder private func icon(_ entry: LaunchEntry) -> some View {
        if case let .application(url) = entry.action {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
        } else {
            Image(systemName: entry.symbol).font(.system(size: 18)).foregroundStyle(accent)
        }
    }
    private var chatContent: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Provider", selection: Binding(get: { model.settings.provider }, set: { value in model.change { $0.provider = value } })) {
                    ForEach(QuickChatProvider.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 112).disabled(chat.replying).accessibilityLabel("Chat provider")
                Spacer()
                Button { model.tab = "history" } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                    .buttonStyle(.plain).foregroundStyle(accent).disabled(chat.replying)
                Button("New Chat") { chat.newChat(); focus = "chat" }.buttonStyle(.plain).foregroundStyle(accent)
                    .keyboardShortcut("n", modifiers: .command)
            }.font(.system(size: 12)).padding(.horizontal, 22).padding(.vertical, 12)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if chat.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Image(systemName: "sparkle").font(.system(size: 28)).foregroundStyle(accent)
                                Text("A quick question. A little clarity.").font(.system(size: 22, weight: .semibold, design: .rounded))
                                Text("Ask, brainstorm, or polish a few words. Your messages go to \(model.settings.provider.title) through its signed-in command-line client and use your plan’s limits.")
                                    .font(.system(size: 12)).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
                                HStack {
                                    Button("Set up \(model.settings.provider.title)") { NSWorkspace.shared.open(model.settings.provider.setupURL) }
                                    Button("Loki settings") { model.perform?(.settings) }
                                }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent)
                            }.padding(.vertical, 20)
                        }
                        ForEach(chat.messages) { message in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(message.role == "user" ? "YOU" : model.settings.provider.title.uppercased())
                                        .font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(message.role == "user" ? LokiStyle.muted : accent)
                                    Spacer()
                                    if !message.text.isEmpty {
                                        Button {
                                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string)
                                        } label: { Image(systemName: "doc.on.doc") }
                                            .buttonStyle(.plain).foregroundStyle(LokiStyle.muted).help("Copy message").accessibilityLabel("Copy message")
                                    }
                                }
                                if message.text.isEmpty { ProgressView().controlSize(.small) }
                                else { Text(message.text).font(.system(size: 13)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let error = chat.error { Text(error).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                        if let error = chat.historyError { Text(error).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(.horizontal, 22).padding(.bottom, 16)
                }
                .onChange(of: chat.messages) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: chat.error) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            HStack(alignment: .center, spacing: 12) {
                TextField("Ask \(model.settings.provider.title)…", text: $chat.draft, axis: .vertical)
                    .lineLimit(1...4).textFieldStyle(.plain).font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true).frame(minHeight: 26)
                    .focused($focus, equals: "chat")
                    .onAppear { DispatchQueue.main.async { focus = "chat" } }
                    .accessibilityLabel("Chat message").onSubmit { chat.send(settings: model.settings) }
                    .disabled(chat.replying)
                if chat.replying {
                    Button { chat.stop() } label: { Image(systemName: "stop.fill").frame(width: 26, height: 26) }
                        .buttonStyle(.plain).foregroundStyle(accent).help("Stop reply").accessibilityLabel("Stop reply")
                } else {
                    Button { chat.send(settings: model.settings) } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 25)).frame(width: 26, height: 26) }
                        .buttonStyle(.plain).foregroundStyle(chat.canSend ? accent : LokiStyle.muted).disabled(!chat.canSend)
                        .help("Send message").accessibilityLabel("Send message")
                }
            }.padding(14).background(LokiStyle.surface, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 18).padding(.bottom, 16)
        }.frame(maxHeight: .infinity)
    }
    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { model.tab = "chat" } label: { Label("Back to chat", systemImage: "chevron.left") }.buttonStyle(.plain)
                Spacer()
                Text("Chat history").font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            TextField("Find a chat…", text: $historyQuery).textFieldStyle(.roundedBorder)
                .focused($focus, equals: "history").accessibilityLabel("Search chat history")
                .onAppear { DispatchQueue.main.async { focus = "history" } }
            ScrollView {
                LazyVStack(spacing: 8) {
                    if chat.conversations.isEmpty {
                        Text("Your conversations will appear here after you send a message. They stay on this Mac until you delete them.")
                            .font(.system(size: 13)).foregroundStyle(LokiStyle.muted).padding(.vertical, 30)
                    } else if historyResults.isEmpty {
                        Text("No matching chats").foregroundStyle(LokiStyle.muted).padding(.vertical, 30)
                    }
                    ForEach(historyResults) { conversation in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                Button {
                                    if model.openConversation(conversation.id) { deletingConversation = nil }
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(conversation.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                        HStack(spacing: 8) {
                                            Text(conversation.provider.title)
                                            Text(conversation.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                            if conversation.id == chat.activeConversationID { Text("Current").foregroundStyle(accent) }
                                        }.font(.system(size: 10)).foregroundStyle(LokiStyle.muted)
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel("Open chat: \(conversation.title), \(conversation.provider.title)")
                                Button { deletingConversation = conversation.id } label: { Image(systemName: "trash") }
                                    .buttonStyle(.plain).foregroundStyle(LokiStyle.muted).accessibilityLabel("Delete chat: \(conversation.title)")
                            }
                            if deletingConversation == conversation.id {
                                HStack {
                                    Text("Delete this saved chat?").font(.caption)
                                    Spacer()
                                    Button("Cancel") { deletingConversation = nil }.buttonStyle(.plain)
                                    Button("Delete", role: .destructive) {
                                        if chat.deleteConversation(conversation.id) { deletingConversation = nil }
                                    }.buttonStyle(.bordered)
                                }
                            }
                        }.padding(12).background(LokiStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }.frame(maxHeight: .infinity)
            if let error = chat.historyError ?? model.settingsError {
                Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(20).frame(maxHeight: .infinity)
    }
    private var historyResults: [QuickChatConversation] {
        let query = historyQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return chat.conversations.filter { query.isEmpty || $0.title.localizedStandardContains(query) || $0.provider.title.localizedStandardContains(query) }
    }
}

struct LauncherSettingsView: View {
    @ObservedObject var model: LauncherModel
    var accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ADD-ONS / LOKI LAUNCH").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(LokiStyle.muted)
            Toggle("Enable Loki Launch", isOn: Binding(get: { model.settings.enabled }, set: { value in model.change { $0.enabled = value } }))
                .toggleStyle(.switch).tint(accent).font(.system(size: 14, weight: .medium))
            Text("A shortcut to your apps, Loki commands, and a quick conversation. Optional, and off by default.")
                .font(.system(size: 12)).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
            if model.settings.enabled {
                HStack {
                    Text("Global shortcut").font(.system(size: 12))
                    Spacer()
                    LauncherShortcutPicker(model: model).frame(width: 172, height: 30)
                    Button("Reset") { _ = model.setShortcut(LaunchShortcut()) }.buttonStyle(.plain).foregroundStyle(accent)
                }
                Text("Click the shortcut to choose its modifiers and key. The default is ⇧Space (either Shift key); ⌃⌥L still opens the shelf.")
                    .font(.system(size: 11)).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
                if let error = model.shortcutError { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                HStack {
                    Picker("Quick Chat provider", selection: Binding(get: { model.settings.provider }, set: { value in model.change { $0.provider = value } })) {
                        ForEach(QuickChatProvider.allCases) { Text($0.title).tag($0) }
                    }.frame(maxWidth: 290)
                    Spacer()
                    Button("Open Loki Launch") { model.openPanel?() }.buttonStyle(.plain).foregroundStyle(accent)
                }.font(.system(size: 12))
                ForEach(QuickChatProvider.allCases) { provider in providerRow(provider) }
                Text("Sign in once using the command above in Terminal. Loki uses that client’s subscription login; it does not collect tokens or use API-key billing. Chat is sent only when you press Send. History is saved locally; changing providers or disabling the add-on starts a fresh chat and keeps earlier conversations in History.")
                    .font(.system(size: 11)).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.settingsError { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(LokiStyle.surface, in: RoundedRectangle(cornerRadius: 14))
    }
    private func providerRow(_ provider: QuickChatProvider) -> some View {
        let path = QuickChatExecutable.find(provider, customPath: model.settings.path(for: provider))
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: path == nil ? "circle.dashed" : "checkmark.circle").foregroundStyle(path == nil ? LokiStyle.muted : accent)
                Text(provider.title).fontWeight(.medium)
                Text(path == nil ? "Client not found" : "Client found").foregroundStyle(LokiStyle.muted)
                Spacer()
                Button("Setup") { NSWorkspace.shared.open(provider.setupURL) }
                Button("Choose client…") { choose(provider) }
                if !model.settings.path(for: provider).isEmpty {
                    Button("Auto") { model.change { if provider == .claude { $0.claudePath = "" } else { $0.codexPath = "" } } }
                }
            }.font(.system(size: 11)).buttonStyle(.plain)
            Text(provider.loginCommand).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).foregroundStyle(accent)
            if let path { Text(path.path).font(.system(size: 10)).foregroundStyle(LokiStyle.muted).lineLimit(1).truncationMode(.middle).help(path.path) }
        }.padding(12).background(LokiStyle.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
    }
    private func choose(_ provider: QuickChatProvider) {
        let picker = NSOpenPanel()
        picker.title = "Choose the \(provider.title) command-line executable"
        picker.canChooseDirectories = false; picker.allowsMultipleSelection = false; picker.showsHiddenFiles = true
        picker.treatsFilePackagesAsDirectories = true
        guard picker.runModal() == .OK, let url = picker.url else { return }
        guard FileManager.default.isExecutableFile(atPath: url.path) else { model.settingsError = "Choose an executable command-line client."; return }
        model.change { if provider == .claude { $0.claudePath = url.path } else { $0.codexPath = url.path } }
    }
}
