import Foundation
import Darwin

@main struct AddOnTests {
    @MainActor static func main() async throws {
        var passed = 0
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
            passed += 1; print("PASS: \(name)")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("loki-addon-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = root.appendingPathComponent("Add-ons")
        try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
        func fixture(_ name: String, id: String? = nil, script: String = "cat >/dev/null\nprintf 'hello from an add-on'\n", mutate: (inout [String: Any]) -> Void = { _ in }) throws -> URL {
            let folder = catalog.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var manifest: [String: Any] = ["schemaVersion": 1, "id": id ?? name, "name": "Test \(name)", "version": "1.0.0", "description": "Test add-on",
                "commands": [["id": "run", "title": "Run Test", "type": "script", "runtime": "shell", "entrypoint": "run.sh", "inputs": [["id": "text", "label": "Text", "type": "text", "required": true]]]]]
            mutate(&manifest)
            try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
            try Data(script.utf8).write(to: folder.appendingPathComponent("run.sh"))
            return folder
        }
        let first = try fixture("valid")
        check("IDs cannot escape installation or become hidden folders", [".", "..", ".hidden", "../escape", "/absolute"].allSatisfy { !AddOnCatalog.validID($0) })
        let fifo = try fixture("fifo")
        try FileManager.default.removeItem(at: fifo.appendingPathComponent("manifest.json"))
        check("FIFO fixture created", mkfifo(fifo.appendingPathComponent("manifest.json").path, 0o600) == 0)
        let fifoStart = Date()
        do { _ = try AddOnCatalog.load(fifo); check("Special files cannot stall package loading", false) }
        catch { check("Special files cannot stall package loading", Date().timeIntervalSince(fifoStart) < 1) }
        try FileManager.default.removeItem(at: fifo)
        let package = try AddOnCatalog.load(first)
        check("Valid packages load without execution", package.id == "valid" && package.manifest.commands.count == 1)
        check("Fingerprint is stable across reads", try! AddOnCatalog.load(first).fingerprint == package.fingerprint)
        try Data("private helper".utf8).write(to: first.appendingPathComponent(".helper"))
        check("Hidden helper changes are included in review fingerprint", try! AddOnCatalog.load(first).fingerprint != package.fingerprint)
        let command = package.manifest.commands[0]
        do { _ = try AddOnCatalog.inputs([:], for: command); check("Required input enforced", false) }
        catch { check("Required input enforced", true) }
        let fields = try AddOnCatalog.inputs(["text": "$(touch /tmp/never-run-this)", "undeclared": "ignore"], for: command)
        check("Only declared inputs reach scripts", fields.count == 1 && fields["text"]?.contains("$(") == true)
        do { _ = try AddOnCatalog.file("../outside", in: first); check("Path traversal rejected", false) }
        catch { check("Path traversal rejected", true) }
        do { _ = try AddOnCatalog.file("/etc/passwd", in: first); check("Absolute entrypoints rejected", false) }
        catch { check("Absolute entrypoints rejected", true) }
        let external = root.appendingPathComponent("outside")
        try Data("outside".utf8).write(to: external)
        try FileManager.default.createSymbolicLink(at: first.appendingPathComponent("escape"), withDestinationURL: external)
        do { _ = try AddOnCatalog.load(first); check("Symlink escapes rejected", false) }
        catch { check("Symlink escapes rejected", true) }
        try FileManager.default.removeItem(at: first.appendingPathComponent("escape"))
        _ = try fixture("unsupported") { $0["schemaVersion"] = 99 }
        _ = try fixture("empty") { $0["commands"] = [] }
        _ = try fixture("bad-id", id: "../escape")
        let scan = AddOnCatalog.scan(catalog)
        check("Malformed packages do not hide valid ones", scan.packages.count == 1 && scan.issues.count == 3)
        let duplicate = try fixture("duplicate", id: "valid")
        check("Duplicate IDs disable all conflicting packages", AddOnCatalog.scan(catalog).packages.isEmpty)
        try FileManager.default.removeItem(at: duplicate)
        let manager = AddOnManager(folder: catalog, watch: false)
        func settle() async throws {
            let deadline = Date().addingTimeInterval(5)
            while manager.scanning && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        }
        try await settle()
        let current = manager.packages.first!
        check("Discovery does not enable code", !manager.enabled(current))
        check("Explicit enable persists approval", manager.setEnabled(true, package: current) && manager.enabled(current))
        let session = AddOnSession(manager: manager)
        session.open(package: current, command: current.manifest.commands[0]); session.inputs["text"] = "test"
        session.run()
        var deadline = Date().addingTimeInterval(5)
        while session.running && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        check("Native forms execute scripts and display output", session.result?.text == "hello from an add-on" && session.error == nil)
        var webError: String?
        session.webReply = { _, _, error in webError = error }
        session.run(commandID: "undeclared", values: ["text": "test"], webRequestID: "invalid")
        check("Undeclared bridge commands are rejected without fallback execution", webError != nil && !session.running)
        try Data("cat >/dev/null\nprintf 'updated'\n".utf8).write(to: first.appendingPathComponent("run.sh"))
        manager.reload(); try await settle()
        let updated = manager.packages.first!
        check("Changed code requires fresh enablement", !manager.enabled(updated) && manager.needsReview(updated))
        check("Hot reload invalidates an open command", session.command == nil && session.error != nil)
        check("Updated package can be enabled without restarting", manager.setEnabled(true, package: updated))
        session.open(package: updated, command: updated.manifest.commands[0]); session.inputs["text"] = "again"; session.run()
        deadline = Date().addingTimeInterval(5)
        while session.running && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        check("Updated code runs without rebuilding the host", session.result?.text == "updated")
        manager.setEnabled(false, package: updated)
        check("Disabling removes availability immediately", manager.package(updated.id) == nil && session.command == nil)
        let retained = AddOnManager(folder: catalog, watch: false); _ = retained
        let rootPreferences = root.appendingPathComponent("addons.json")
        let persisted = try JSONDecoder().decode(AddOnPreferences.self, from: Data(contentsOf: rootPreferences))
        check("Disabled state survives restart", persisted.approved.isEmpty)
        let result = AddOnResult.parse("{\"title\":\"Done\",\"text\":\"hello\",\"copyText\":\"copy\"}")
        check("Structured output is decoded", result.title == "Done" && result.copyText == "copy")
        check("Plain output preserves meaningful whitespace", AddOnResult.parse("  indented\n\n").text == "  indented\n\n")
        let cache = AddOnScanner()
        let cached = cache.scan(catalog)
        check("Unchanged metadata scan preserves packages", cache.scan(catalog) == cached)
        try Data("cat >/dev/null\nprintf 'changed'\n".utf8).write(to: first.appendingPathComponent("run.sh"))
        check("Cached scanning detects changed bytes", cache.scan(catalog).packages.first?.fingerprint != cached.packages.first?.fingerprint)
        let corruptRoot = root.appendingPathComponent("corrupt")
        try FileManager.default.createDirectory(at: corruptRoot, withIntermediateDirectories: true)
        let corruptPrefs = corruptRoot.appendingPathComponent("addons.json")
        try Data("broken preferences".utf8).write(to: corruptPrefs)
        let corrupt = AddOnManager(folder: corruptRoot.appendingPathComponent("Add-ons"), watch: false)
        check("Unreadable approvals never enable code", !corrupt.setEnabled(true, package: updated) && !corrupt.enabled(updated))
        check("Unreadable approvals remain intact", try! String(contentsOf: corruptPrefs, encoding: .utf8) == "broken preferences")
        let tree = try fixture("tree", script: "/bin/sleep 10 &\nwait\n")
        let runner = LocalProcessRunner(), start = Date()
        do {
            _ = try runner.run(executable: URL(fileURLWithPath: "/bin/zsh"), arguments: ["-f", tree.appendingPathComponent("run.sh").path], directory: tree, environment: ["PATH": "/usr/bin:/bin"], timeout: 0.1)
            check("Timeout stops a script's child processes", false)
        } catch { check("Timeout stops a script's child processes", error.localizedDescription.contains("too long") && Date().timeIntervalSince(start) < 2) }
        manager.reload(); manager.reload(); try await settle()
        let slow = manager.packages.first { $0.id == "tree" }!
        check("Slow command can be explicitly enabled", manager.setEnabled(true, package: slow))
        session.open(package: slow, command: slow.manifest.commands[0])
        webError = nil; session.webReply = { _, _, error in webError = error }
        session.run(values: ["text": "test"], webRequestID: "stop")
        try await Task.sleep(nanoseconds: 50_000_000)
        manager.setEnabled(false, package: slow)
        check("Disable stops active commands and rejects their web promise", !session.running && session.command == nil && webError == "Command stopped.")
        try await Task.sleep(nanoseconds: 150_000_000)
        check("Cancelled command cannot overwrite session state later", session.result == nil && !session.running)
        let examples = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("addons/examples")
        for example in try FileManager.default.contentsOfDirectory(at: examples, includingPropertiesForKeys: nil) {
            let package = try AddOnCatalog.load(example)
            check("Bundled example validates: \(package.id)", !package.manifest.commands.isEmpty)
            let request = try JSONSerialization.data(withJSONObject: ["inputs": ["text": "  Loki\n\n", "mode": "UPPERCASE"]])
            let output = try LocalProcessRunner().run(executable: URL(fileURLWithPath: "/bin/zsh"), arguments: ["-f", example.appendingPathComponent("transform.sh").path], input: String(decoding: request, as: UTF8.self), directory: example, environment: ["PATH": "/usr/bin:/bin"])
            check("Example preserves input whitespace: \(package.id)", output.status == 0 && output.stdout == "  LOKI\n\n")
        }
        print("\(passed) add-on tests passed")
    }
}
