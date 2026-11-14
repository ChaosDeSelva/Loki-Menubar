import AppKit
import Combine

@MainActor
final class AddOnManager: ObservableObject {
    let folder: URL
    @Published private(set) var packages: [InstalledAddOn] = []
    @Published private(set) var issues: [AddOnIssue] = []
    @Published private(set) var revision = 0
    @Published private(set) var scanning = false
    @Published var error: String?
    private var preferences = AddOnPreferences()
    private var canSave = true
    private let preferencesURL: URL
    private var timer: Timer?
    private var lastScan = AddOnScan()
    private let scanner = AddOnScanner()
    private var reloadQueued = false

    init(folder: URL? = nil, watch: Bool = true) {
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Loki/Add-ons")
        preferencesURL = self.folder.deletingLastPathComponent().appendingPathComponent("addons.json")
        do {
            if FileManager.default.fileExists(atPath: preferencesURL.path) {
                preferences = try JSONDecoder().decode(AddOnPreferences.self, from: Data(contentsOf: preferencesURL))
                guard preferences.version == 1 else { throw LauncherFailure("Unsupported add-on preferences version.") }
            }
        } catch { self.error = "Add-on preferences could not be read and were preserved. \(error.localizedDescription)"; canSave = false; preferences = AddOnPreferences() }
        reload()
        if watch {
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
        }
    }
    deinit { timer?.invalidate() }
    func enabled(_ package: InstalledAddOn) -> Bool { preferences.approved[package.id] == package.fingerprint }
    func needsReview(_ package: InstalledAddOn) -> Bool { preferences.approved[package.id] != nil && !enabled(package) }
    func package(_ id: String) -> InstalledAddOn? { packages.first { $0.id == id && enabled($0) } }
    func reload() {
        guard !scanning else { reloadQueued = true; return }
        scanning = true
        let folder = folder, scanner = scanner
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { scanner.scan(folder) }.value
            guard let self else { return }
            self.scanning = false
            defer { if self.reloadQueued { self.reloadQueued = false; self.reload() } }
            guard result != self.lastScan else { return }
            self.lastScan = result; self.packages = result.packages; self.issues = result.issues; self.revision += 1
        }
    }
    @discardableResult
    func setEnabled(_ enabled: Bool, package: InstalledAddOn) -> Bool {
        guard canSave else { return false }
        do {
            var candidate = preferences
            if enabled {
                let current = try AddOnCatalog.load(package.folder)
                guard current.fingerprint == package.fingerprint else { reload(); throw LauncherFailure("The add-on changed. Review its updated details and enable it again.") }
                candidate.approved[package.id] = current.fingerprint
            } else { candidate.approved.removeValue(forKey: package.id) }
            try FileManager.default.createDirectory(at: preferencesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(candidate).write(to: preferencesURL, options: .atomic)
            preferences = candidate; error = nil; revision += 1
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func openFolder() {
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); NSWorkspace.shared.open(folder) }
        catch { self.error = error.localizedDescription }
    }
    func install(from source: URL) {
        do {
            let package = try AddOnCatalog.load(source)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(package.id)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw LauncherFailure("\(package.manifest.name) is already installed. Edit or replace its folder to update it; Loki will reload it automatically.")
            }
            let staging = folder.appendingPathComponent(".install-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: staging) }
            try FileManager.default.copyItem(at: source, to: staging)
            _ = try AddOnCatalog.load(staging)
            try FileManager.default.moveItem(at: staging, to: destination)
            error = nil; reload()
        } catch { self.error = error.localizedDescription }
    }
    func installExamples() {
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("AddOnExamples"),
              let folders = try? FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else {
            error = "Example add-ons are missing from this app bundle."; return
        }
        for example in folders where (try? example.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            guard let package = try? AddOnCatalog.load(example), !FileManager.default.fileExists(atPath: folder.appendingPathComponent(package.id).path) else { continue }
            install(from: example)
        }
    }
}

@MainActor
final class AddOnSession: ObservableObject {
    @Published private(set) var package: InstalledAddOn?
    @Published private(set) var command: AddOnCommand?
    @Published var inputs: [String: String] = [:]
    @Published private(set) var result: AddOnResult?
    @Published private(set) var error: String?
    @Published private(set) var running = false
    private var process: LocalProcessRunner?
    private var requestID = UUID()
    private var pendingWebRequestID: String?
    private let manager: AddOnManager
    private var observation: AnyCancellable?
    var webReply: ((String, AddOnResult?, String?) -> Void)?
    var webOwner: UUID?

    init(manager: AddOnManager) {
        self.manager = manager
        observation = manager.$revision.dropFirst().sink { [weak self] _ in
            guard let self, let package = self.package else { return }
            if self.manager.package(package.id)?.fingerprint != package.fingerprint {
                self.stop(); self.error = "This add-on changed, was disabled, or was removed. Review it in Add-ons before running it again."
                self.command = nil; self.webReply = nil
            }
        }
    }
    func open(package: InstalledAddOn, command: AddOnCommand) {
        stop(); self.package = package; self.command = command; result = nil; error = nil; webReply = nil
        guard manager.package(package.id)?.fingerprint == package.fingerprint,
              package.manifest.commands.contains(command),
              let current = try? AddOnCatalog.load(package.folder), current.fingerprint == package.fingerprint else {
            self.command = nil; error = "The add-on changed. Review and enable the updated version in Add-ons."; manager.reload(); return
        }
        inputs = Dictionary(uniqueKeysWithValues: (command.inputs ?? []).map { ($0.id, $0.value ?? ($0.type == .toggle ? "false" : $0.options?.first ?? "")) })
    }
    func clear() { stop(); package = nil; command = nil; inputs = [:]; result = nil; error = nil; webReply = nil; webOwner = nil }
    func run(commandID: String? = nil, values: [String: String]? = nil, webRequestID: String? = nil) {
        let selected = commandID == nil ? command : package?.manifest.commands.first(where: { $0.id == commandID })
        guard !running, let package, manager.package(package.id)?.fingerprint == package.fingerprint,
              let command = selected,
              command.type == .script else {
            if let webRequestID { webReply?(webRequestID, nil, "Command unavailable or another command is running.") }
            return
        }
        do {
            let fields = try AddOnCatalog.inputs(values ?? inputs, for: command)
            let dataFolder = manager.folder.deletingLastPathComponent().appendingPathComponent("Add-on Data").appendingPathComponent(package.id)
            try FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let request = try JSONSerialization.data(withJSONObject: ["apiVersion": 1, "command": command.id, "inputs": fields,
                "context": ["addonID": package.id, "dataDirectory": dataFolder.path, "packageDirectory": package.folder.path]])
            let id = UUID(); requestID = id
            pendingWebRequestID = webRequestID
            let process = LocalProcessRunner(); self.process = process
            running = true; result = nil; error = nil
            Task { [weak self] in
                do {
                    let output = try await Task.detached(priority: .userInitiated) {
                        let current = try AddOnCatalog.load(package.folder)
                        guard current.fingerprint == package.fingerprint else { throw LauncherFailure("The add-on changed. Enable the updated version before running it.") }
                        let script = try AddOnCatalog.file(command.entrypoint, in: package.folder)
                        var environment = QuickChatRequest.environment(ProcessInfo.processInfo.environment, home: NSHomeDirectory())
                        environment.removeValue(forKey: "CODEX_HOME"); environment.removeValue(forKey: "CLAUDE_CONFIG_DIR")
                        environment["LOKI_ADDON_DATA_DIR"] = dataFolder.path
                        let executable: URL, arguments: [String]
                        switch command.runtime {
                        case .shell: executable = URL(fileURLWithPath: "/bin/zsh"); arguments = ["-f", script.path]
                        case .python: executable = URL(fileURLWithPath: "/usr/bin/python3"); arguments = [script.path]
                        case .node:
                            let candidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node", NSHomeDirectory() + "/.local/bin/node"]
                            guard let node = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw LauncherFailure("This add-on needs Node.js installed in /opt/homebrew/bin, /usr/local/bin, or ~/.local/bin.") }
                            executable = URL(fileURLWithPath: node); arguments = [script.path]
                        case .executable: executable = script; arguments = []
                        case nil: throw LauncherFailure("Missing script runtime.")
                        }
                        let output = try process.run(executable: executable, arguments: arguments, input: String(decoding: request, as: UTF8.self),
                            directory: package.folder, environment: environment, timeout: command.timeout ?? 30)
                        guard output.status == 0 else { throw LauncherFailure("Command exited with code \(output.status). \(String(output.stderr.suffix(2000)))") }
                        return AddOnResult.parse(output.stdout)
                    }.value
                    guard let self, self.requestID == id else { return }
                    self.result = output; self.running = false; self.process = nil
                    self.pendingWebRequestID = nil
                    if let webRequestID { self.webReply?(webRequestID, output, nil) }
                } catch {
                    guard let self, self.requestID == id else { return }
                    self.error = error.localizedDescription; self.running = false; self.process = nil
                    self.pendingWebRequestID = nil
                    if let webRequestID { self.webReply?(webRequestID, nil, error.localizedDescription) }
                }
            }
        } catch {
            self.error = error.localizedDescription
            if let webRequestID { webReply?(webRequestID, nil, error.localizedDescription) }
        }
    }
    func stop() {
        requestID = UUID(); process?.cancel(reason: "Command stopped."); process = nil
        if running { error = "Command stopped." }
        running = false
        if let id = pendingWebRequestID { webReply?(id, nil, "Command stopped.") }
        pendingWebRequestID = nil
    }
}
