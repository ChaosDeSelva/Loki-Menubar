import AppKit
import SwiftUI
import WebKit

struct AddOnSettingsView: View {
    @ObservedObject var manager: AddOnManager
    @State private var enabling: InstalledAddOn?
    var accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RELOADABLE ADD-ONS").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(LokiStyle.muted)
            Text("New tools. No new Loki build.").font(.system(size: 20, weight: .semibold, design: .rounded))
            Text("Install an add-on folder, enable it, and find its commands in Loki Launch. Forms and custom interfaces open right in the launcher. Folder changes are detected automatically.")
                .font(.system(size: 12)).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Install folder…") { chooseFolder() }
                Button("Open folder") { manager.openFolder() }
                Button("Add examples") { manager.installExamples() }
                Spacer()
                Button { manager.reload() } label: { Image(systemName: "arrow.clockwise") }.help("Reload add-ons").accessibilityLabel("Reload add-ons")
            }.font(.system(size: 12)).buttonStyle(.bordered)
            if manager.packages.isEmpty && manager.issues.isEmpty {
                Text("No add-ons installed yet. Add the examples to try a native text tool and a custom text workbench.")
                    .font(.caption).foregroundStyle(LokiStyle.muted).padding(.vertical, 10)
            }
            ForEach(manager.packages) { package in
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(get: { manager.enabled(package) }, set: { value in
                        if value { enabling = package } else { manager.setEnabled(false, package: package) }
                    })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(package.manifest.name).font(.system(size: 13, weight: .semibold))
                            Text("v\(package.manifest.version) · \(package.manifest.commands.count) commands\(package.manifest.author.map { " · " + $0 } ?? "")")
                                .font(.system(size: 10)).foregroundStyle(LokiStyle.muted)
                        }
                    }.toggleStyle(.switch).tint(accent)
                    Text(package.manifest.description).font(.system(size: 12)).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
                    if manager.needsReview(package) { Text("Updated files detected. Enable again to use this version.").font(.caption).foregroundStyle(.orange) }
                    Text(package.runsScripts ? "Runs local scripts with your account’s file and network access." : "Local custom interface; no native scripts.")
                        .font(.system(size: 10)).foregroundStyle(LokiStyle.muted)
                }.padding(14).background(LokiStyle.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            }
            ForEach(manager.issues) { Text($0.message).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if let error = manager.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            Text("An update reloads without restarting Loki. Changed code is disabled until you enable the updated version. Disabling an add-on removes its commands and stops its running command.")
                .font(.system(size: 11)).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(LokiStyle.surface, in: RoundedRectangle(cornerRadius: 14))
        .confirmationDialog(enabling.map { "Enable \($0.manifest.name)?" } ?? "Enable add-on?", isPresented: Binding(get: { enabling != nil }, set: { if !$0 { enabling = nil } }), titleVisibility: .visible) {
            if let package = enabling {
                Button("Enable \(package.manifest.name)") { manager.setEnabled(true, package: package); enabling = nil }
            }
            Button("Cancel", role: .cancel) { enabling = nil }
        } message: {
            Text(enabling?.runsScripts == true ? "This add-on runs local code when you choose one of its commands. It can access files and the network as your account. Enable only code you trust." : "This add-on can run its bundled HTML and JavaScript in Loki. It cannot run native commands unless they are declared in its manifest. Enable only add-ons you trust.")
        }
    }
    private func chooseFolder() {
        let picker = NSOpenPanel(); picker.title = "Choose an add-on folder containing manifest.json"
        picker.canChooseDirectories = true; picker.canChooseFiles = false; picker.allowsMultipleSelection = false
        if picker.runModal() == .OK, let url = picker.url { manager.install(from: url) }
    }
}

struct AddOnRunnerView: View {
    @ObservedObject var session: AddOnSession
    let back: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: back) { Label("Back", systemImage: "chevron.left") }.buttonStyle(.plain)
                Spacer()
                Text(session.package?.manifest.name ?? "Add-on").foregroundStyle(LokiStyle.muted)
                if session.running { ProgressView().controlSize(.mini); Button("Stop") { session.stop() }.buttonStyle(.plain) }
            }.font(.system(size: 11)).padding(.horizontal, 20).padding(.top, 14)
            if let package = session.package, let command = session.command {
                if command.type == .view {
                    AddOnWebView(package: package, command: command, session: session).id(package.fingerprint + command.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(command.title).font(.system(size: 21, weight: .semibold, design: .rounded))
                            if let subtitle = command.subtitle { Text(subtitle).font(.caption).foregroundStyle(LokiStyle.muted) }
                            ForEach(command.inputs ?? []) { field in input(field).disabled(session.running) }
                            HStack {
                                if session.running {
                                    ProgressView().controlSize(.small)
                                    Button("Stop") { session.stop() }
                                } else { Button("Run") { session.run() }.keyboardShortcut(.return, modifiers: .command) }
                                Text("⌘↵").font(.caption).foregroundStyle(LokiStyle.muted)
                                Spacer()
                            }.buttonStyle(.bordered)
                            if let result = session.result {
                                Divider()
                                HStack {
                                    Text(result.title ?? "Result").font(.headline)
                                    Spacer()
                                    Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result.copyText ?? result.text, forType: .string) }.buttonStyle(.plain)
                                }
                                Text(result.text.isEmpty ? "Completed." : result.text).font(.system(size: 13)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }
                        }.padding(20)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else { Spacer() }
            if let error = session.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled).padding(.horizontal, 20).padding(.bottom, 12) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    @ViewBuilder private func input(_ field: AddOnField) -> some View {
        let binding = Binding(get: { session.inputs[field.id] ?? "" }, set: { session.inputs[field.id] = $0 })
        VStack(alignment: .leading, spacing: 6) {
            Text(field.label + (field.required == true ? " *" : "")).font(.system(size: 12, weight: .medium))
            switch field.type {
            case .text: TextField(field.placeholder ?? "", text: binding).textFieldStyle(.roundedBorder)
            case .multiline: TextField(field.placeholder ?? "", text: binding, axis: .vertical).lineLimit(3...6).textFieldStyle(.roundedBorder)
            case .choice: Picker(field.label, selection: binding) { ForEach(field.options ?? [], id: \.self) { Text($0).tag($0) } }.labelsHidden()
            case .toggle: Toggle(field.label, isOn: Binding(get: { binding.wrappedValue == "true" }, set: { binding.wrappedValue = $0 ? "true" : "false" })).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}

struct AddOnWebView: NSViewRepresentable {
    let package: InstalledAddOn
    let command: AddOnCommand
    let session: AddOnSession
    func makeCoordinator() -> Coordinator { Coordinator(session: session, folder: package.folder) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(context.coordinator, name: "loki")
        let bridge = """
        (() => {
          const waiting = new Map(); let next = 0;
          window.loki = Object.freeze({apiVersion: 1, run(command, inputs = {}) {
            return new Promise((resolve, reject) => {
              if (waiting.size) { reject(new Error('Another command is running.')); return; }
              const id = String(++next); waiting.set(id, {resolve, reject});
              try { window.webkit.messageHandlers.loki.postMessage({id, command, inputs}); }
              catch (error) { waiting.delete(id); reject(error); }
            });
          }});
          window.addEventListener('loki:result', event => {
            const {id, result, error} = event.detail; const request = waiting.get(id);
            if (!request) return; waiting.delete(id);
            error ? request.reject(new Error(error)) : request.resolve(result);
          });
        })();
        """
        configuration.userContentController.addUserScript(WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator; web.underPageBackgroundColor = NSColor(red: 0.055, green: 0.075, blue: 0.065, alpha: 1)
        context.coordinator.web = web
        session.webOwner = context.coordinator.owner
        session.webReply = { [weak web] id, result, error in
            var payload: [String: Any] = ["id": id]
            if let result, let data = try? JSONEncoder().encode(result), let object = try? JSONSerialization.jsonObject(with: data) { payload["result"] = object }
            if let error { payload["error"] = error }
            web?.callAsyncJavaScript("window.dispatchEvent(new CustomEvent('loki:result', { detail: payload }));", arguments: ["payload": payload], in: nil, in: .page, completionHandler: nil)
        }
        // Bundled interfaces stay local; network access belongs in explicitly enabled script commands.
        let rules = "[" + ["^https?://", "^wss?://", "^ftp://"].map {
            "{\"trigger\":{\"url-filter\":\"\($0)\"},\"action\":{\"type\":\"block\"}}"
        }.joined(separator: ",") + "]"
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "LokiLocalAddOns-v1", encodedContentRuleList: rules) { [weak web] list, error in
            DispatchQueue.main.async {
                guard let web else { return }
                guard let list, error == nil else { web.loadHTMLString("<p>Could not initialize local add-on protections.</p>", baseURL: nil); return }
                web.configuration.userContentController.add(list)
                do {
                    let url = try AddOnCatalog.file(command.entrypoint, in: package.folder)
                    web.loadFileURL(url, allowingReadAccessTo: package.folder)
                } catch { web.loadHTMLString("<p>The add-on entrypoint is unavailable. Reload it in Add-ons.</p>", baseURL: nil) }
            }
        }
        return web
    }
    func updateNSView(_ web: WKWebView, context: Context) {}
    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        web.stopLoading(); web.configuration.userContentController.removeScriptMessageHandler(forName: "loki")
        if coordinator.session?.webOwner == coordinator.owner {
            coordinator.session?.stop()
            coordinator.session?.webReply = nil; coordinator.session?.webOwner = nil
        }
    }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var session: AddOnSession?
        weak var web: WKWebView?
        let folder: URL
        let owner = UUID()
        init(session: AddOnSession, folder: URL) { self.session = session; self.folder = folder }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard session?.webOwner == owner else { return }
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let id = body["id"] as? String, id.count <= 100 else { return }
            guard let command = body["command"] as? String, let inputs = body["inputs"] as? [String: String], inputs.count <= 20 else {
                session?.webReply?(id, nil, "Pass a declared command ID and an object with string input values."); return
            }
            session?.run(commandID: command, values: inputs, webRequestID: id)
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            let resolved = url.resolvingSymlinksInPath().path
            let local = url.isFileURL && resolved.hasPrefix(folder.resolvingSymlinksInPath().path + "/")
            decisionHandler(local || url.absoluteString == "about:blank" ? .allow : .cancel)
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard session?.webOwner == owner else { return }
            session?.stop()
            webView.loadHTMLString("<p>This interface stopped responding. Go back and open the add-on again.</p>", baseURL: nil)
        }
    }
}
