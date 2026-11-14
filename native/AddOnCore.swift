import Foundation
import CryptoKit
import Darwin

struct AddOnField: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case text, multiline, choice, toggle }
    let id: String
    let label: String
    let type: Kind
    var placeholder: String?
    var required: Bool?
    var options: [String]?
    var value: String?
}

struct AddOnCommand: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case script, view }
    enum Runtime: String, Codable { case shell, python, node, executable }
    let id: String
    let title: String
    let type: Kind
    let entrypoint: String
    var subtitle: String?
    var keywords: [String]?
    var icon: String?
    var runtime: Runtime?
    var inputs: [AddOnField]?
    var timeout: Double?
}

struct AddOnManifest: Codable, Equatable {
    let schemaVersion: Int
    let id: String
    let name: String
    let version: String
    let description: String
    var author: String?
    var icon: String?
    let commands: [AddOnCommand]
}

struct InstalledAddOn: Identifiable, Equatable {
    var id: String { manifest.id }
    let manifest: AddOnManifest
    let folder: URL
    let fingerprint: String
    var runsScripts: Bool { manifest.commands.contains { $0.type == .script } }
}

struct AddOnIssue: Identifiable, Equatable {
    let id: String
    let message: String
}

struct AddOnScan: Equatable {
    var packages: [InstalledAddOn] = []
    var issues: [AddOnIssue] = []
}

struct AddOnPreferences: Codable {
    var version = 1
    var approved: [String: String] = [:]
}

enum AddOnCatalog {
    static func validID(_ id: String) -> Bool {
        guard let first = id.unicodeScalars.first, CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").contains(first) else { return false }
        return id.count <= 80 && id.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-_").contains($0) }
    }
    static func file(_ relative: String, in folder: URL) throws -> URL {
        guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else {
            throw LauncherFailure("Entrypoints must be relative paths inside the add-on folder.")
        }
        let root = folder.resolvingSymlinksInPath().standardizedFileURL
        let result = root.appendingPathComponent(relative).resolvingSymlinksInPath().standardizedFileURL
        guard result.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: result.path) else {
            throw LauncherFailure("Missing or external add-on file: \(relative)")
        }
        guard try result.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw LauncherFailure("The entrypoint must be a regular file: \(relative)")
        }
        return result
    }
    static func load(_ folder: URL) throws -> InstalledAddOn {
        let before = try snapshot(folder)
        let manifestURL = try file("manifest.json", in: folder)
        guard (try manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 128_000 else {
            throw LauncherFailure("manifest.json is too large.")
        }
        let manifest = try JSONDecoder().decode(AddOnManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.schemaVersion == 1 else { throw LauncherFailure("Unsupported add-on schema. This host supports schemaVersion 1.") }
        guard validID(manifest.id), !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.name.count <= 100, !manifest.version.isEmpty, manifest.description.count <= 2000,
              !manifest.commands.isEmpty, manifest.commands.count <= 50 else { throw LauncherFailure("Invalid add-on identity or commands.") }
        var commandIDs = Set<String>()
        for command in manifest.commands {
            guard validID(command.id), commandIDs.insert(command.id).inserted, !command.title.isEmpty, command.title.count <= 100 else {
                throw LauncherFailure("Command IDs must be unique and titles must be between 1 and 100 characters.")
            }
            _ = try file(command.entrypoint, in: folder)
            if command.type == .script && command.runtime == nil { throw LauncherFailure("Script \(command.id) needs a runtime.") }
            if command.type == .view && !["html", "htm"].contains(URL(fileURLWithPath: command.entrypoint).pathExtension.lowercased()) {
                throw LauncherFailure("Custom interfaces must have an HTML entrypoint.")
            }
            if let timeout = command.timeout, !timeout.isFinite || timeout < 1 || timeout > 120 { throw LauncherFailure("Command timeouts must be between 1 and 120 seconds.") }
            var inputs = Set<String>()
            guard (command.inputs?.count ?? 0) <= 20 else { throw LauncherFailure("Commands support at most 20 inputs.") }
            for field in command.inputs ?? [] {
                guard validID(field.id), inputs.insert(field.id).inserted, !field.label.isEmpty, field.label.count <= 200,
                      (field.value?.count ?? 0) <= 32_000 else { throw LauncherFailure("Invalid input ID, label, or default value.") }
                if field.type == .choice {
                    guard let options = field.options, !options.isEmpty, options.count <= 100,
                          Set(options).count == options.count, options.allSatisfy({ !$0.isEmpty && $0.count <= 200 }),
                          field.value == nil || options.contains(field.value!) else { throw LauncherFailure("Choice fields need unique options and a matching default value.") }
                }
                if field.type == .toggle, let value = field.value, !["true", "false"].contains(value) { throw LauncherFailure("Toggle defaults must be true or false.") }
            }
        }
        let root = folder.resolvingSymlinksInPath()
        var hash = SHA256()
        for url in before.files {
            let data = try Data(contentsOf: url)
            hash.update(data: Data(url.path.dropFirst(root.path.count).utf8))
            hash.update(data: Data([0]))
            var size = UInt64(data.count).bigEndian
            withUnsafeBytes(of: &size) { hash.update(data: Data($0)) }
            hash.update(data: data)
        }
        guard try snapshot(folder).stamp == before.stamp else { throw LauncherFailure("The add-on is being updated. Reload it after saving its files.") }
        return InstalledAddOn(manifest: manifest, folder: root, fingerprint: hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
    struct Snapshot { let files: [URL]; let stamp: String }
    static func snapshot(_ folder: URL) throws -> Snapshot {
        var rootInfo = stat()
        guard lstat(folder.path, &rootInfo) == 0, rootInfo.st_mode & mode_t(S_IFMT) == S_IFDIR else {
            throw LauncherFailure("Choose a regular add-on folder, not a symbolic link.")
        }
        let root = folder.resolvingSymlinksInPath().standardizedFileURL
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [], errorHandler: { _, error in
            enumerationError = error; return false
        }) else {
            throw LauncherFailure("Could not read the add-on folder.")
        }
        var paths: [URL] = [], signatures: [String] = [], total: Int64 = 0
        var candidates = [root]
        for case let url as URL in enumerator {
            candidates.append(url)
            guard candidates.count <= 1000 else { throw LauncherFailure("Add-on packages are limited to 1,000 total files and folders.") }
        }
        if let enumerationError { throw enumerationError }
        for url in candidates {
            var info = stat()
            guard lstat(url.path, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            let kind = info.st_mode & mode_t(S_IFMT)
            guard kind == S_IFREG || kind == S_IFDIR else { throw LauncherFailure("Add-on packages can contain only regular files and folders, without symbolic links.") }
            if url == root && kind != S_IFDIR { throw LauncherFailure("Choose an add-on folder.") }
            if kind == S_IFREG {
                total += info.st_size; paths.append(url)
                guard paths.count <= 500, total <= 20_000_000 else { throw LauncherFailure("Add-on packages are limited to 500 files and 20 MB.") }
            }
            signatures.append("\(url.path):\(info.st_ino):\(info.st_mode):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)")
        }
        let stamp = SHA256.hash(data: Data(signatures.sorted().joined(separator: "\u{0}").utf8)).map { String(format: "%02x", $0) }.joined()
        return Snapshot(files: paths.sorted { $0.path < $1.path }, stamp: stamp)
    }
    static func scan(_ folder: URL, loadPackage: (URL) throws -> InstalledAddOn = { try load($0) }) -> AddOnScan {
        var result = AddOnScan()
        guard FileManager.default.fileExists(atPath: folder.path) else { return result }
        do {
            let children = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]).sorted { $0.lastPathComponent < $1.lastPathComponent }
            var duplicates = Set<String>()
            if children.count > 100 { result.issues.append(AddOnIssue(id: "limit", message: "Only the first 100 add-on folders are loaded. Remove unused folders to load the others.")) }
            for child in children.prefix(100) {
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                do {
                    guard (try child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw LauncherFailure("Add-on folders cannot be symbolic links.") }
                    let package = try loadPackage(child)
                    if result.packages.contains(where: { $0.id == package.id }) { duplicates.insert(package.id) }
                    result.packages.append(package)
                } catch { result.issues.append(AddOnIssue(id: child.path, message: "\(child.lastPathComponent): \(error.localizedDescription)")) }
            }
            for id in duplicates {
                result.packages.removeAll { $0.id == id }
                result.issues.append(AddOnIssue(id: "duplicate:" + id, message: "More than one add-on uses ‘\(id)’. Give each add-on a unique ID."))
            }
        } catch { result.issues.append(AddOnIssue(id: folder.path, message: error.localizedDescription)) }
        return result
    }
    static func inputs(_ supplied: [String: String], for command: AddOnCommand) throws -> [String: String] {
        var result: [String: String] = [:]
        for field in command.inputs ?? [] {
            let value = supplied[field.id] ?? field.value ?? (field.type == .toggle ? "false" : field.type == .choice ? field.options?.first ?? "" : "")
            guard value.count <= 32_000 else { throw LauncherFailure("\(field.label) is too long.") }
            if field.required == true && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw LauncherFailure("Enter \(field.label.lowercased()).") }
            if field.type == .choice && !(field.options ?? []).contains(value) { throw LauncherFailure("Choose a valid value for \(field.label.lowercased()).") }
            if field.type == .toggle && !["true", "false"].contains(value) { throw LauncherFailure("Invalid toggle value for \(field.label).") }
            result[field.id] = value
        }
        return result
    }
}

struct AddOnResult: Codable, Equatable {
    var title: String?
    var text: String
    var copyText: String?
    static func parse(_ output: String) -> AddOnResult {
        if let data = output.data(using: .utf8), let result = try? JSONDecoder().decode(AddOnResult.self, from: data) { return result }
        return AddOnResult(text: output)
    }
}

final class AddOnScanner: @unchecked Sendable {
    private var cache: [URL: (stamp: String, package: InstalledAddOn)] = [:]
    private let lock = NSLock()
    func scan(_ folder: URL) -> AddOnScan {
        lock.lock(); defer { lock.unlock() }
        var next: [URL: (stamp: String, package: InstalledAddOn)] = [:]
        let result = AddOnCatalog.scan(folder) { child in
            let stamp = try AddOnCatalog.snapshot(child).stamp
            // Poll metadata cheaply; enable and execution always rehash the package bytes.
            let package = try self.cache[child].flatMap { $0.stamp == stamp ? $0.package : nil } ?? AddOnCatalog.load(child)
            next[child] = (stamp, package)
            return package
        }
        cache = next
        return result
    }
}
