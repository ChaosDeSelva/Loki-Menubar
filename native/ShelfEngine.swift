import Foundation

struct ShelfRecord: Codable, Equatable {
    var id: String
    var title: String
    var app: String
}

struct Realm: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var symbol: String
    var pins: [String]
    var order: [String]
    var tuckedApps: [String]? = nil
    var groups: [String: String]? = nil
    var groupNames: [String]? = nil

    var availableGroups: [String] {
        var names = groupNames ?? ["Work", "Personal", "System"]
        for name in Set((groups ?? [:]).values).sorted() where !names.contains(name) { names.append(name) }
        return names
    }

    mutating func setGroupName(_ proposed: String, replacing old: String? = nil) throws -> String {
        let name = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40 else { throw GroupNameError("Use a group name between 1 and 40 characters.") }
        guard !["All", "Ungrouped"].contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw GroupNameError("All and Ungrouped are reserved filters. Choose another name.")
        }
        var names = availableGroups
        if let old, !names.contains(old) { throw GroupNameError("This group no longer exists.") }
        guard !names.contains(where: { $0 != old && $0.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else {
            throw GroupNameError("A group with that name already exists in this realm.")
        }
        if let old, let index = names.firstIndex(of: old) {
            names[index] = name
            groups = groups?.mapValues { $0 == old ? name : $0 }
        } else { names.append(name) }
        groupNames = names
        return name
    }

    mutating func removeGroup(_ name: String) {
        groupNames = availableGroups.filter { $0 != name }
        groups = groups?.filter { $0.value != name }
    }


    static let defaults = [
        Realm(id: "asgard", name: "Asgard", symbol: "sun.max", pins: [], order: []),
        Realm(id: "midgard", name: "Midgard", symbol: "leaf", pins: [], order: []),
        Realm(id: "jotunheim", name: "Jotunheim", symbol: "snowflake", pins: [], order: [])
    ]
}

struct GroupNameError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct Preferences: Codable {
    var version = 1
    var selectedRealm = "asgard"
    var realms = Realm.defaults
    var accent = "moss"
    var playful = true
    var source = "menu"
    var rehideDelay: Double? = nil
    var autoRehide: Bool? = nil
}

enum ShelfEngine {
    /// Pure planning: discovery never deletes a saved pin or changes another app's position.
    static func arrange(_ items: [ShelfRecord], realm: Realm, query: String, favoritesOnly: Bool) -> [String] {
        let words = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let pins = Set(realm.pins)
        let order = Dictionary(realm.order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        let ranked: [(ShelfRecord, Int)] = items.compactMap { item in
            guard seen.insert(item.id).inserted, !favoritesOnly || pins.contains(item.id) else { return nil }
            let title = item.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let haystack = "\(title) \(item.app)".folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            var rank = 0
            for word in words {
                guard haystack.contains(word) else { return nil }
                rank += title == word ? 0 : title.hasPrefix(word) ? 1 : 2
            }
            return (item, rank)
        }
        return ranked.sorted { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            if pins.contains(a.0.id) != pins.contains(b.0.id) { return pins.contains(a.0.id) }
            if order[a.0.id, default: .max] != order[b.0.id, default: .max] {
                return order[a.0.id, default: .max] < order[b.0.id, default: .max]
            }
            let comparison = a.0.title.localizedStandardCompare(b.0.title)
            return comparison == .orderedSame ? a.0.id < b.0.id : comparison == .orderedAscending
        }.map { $0.0.id }
    }

    static func reordered(_ order: [String], moving id: String, before target: String) -> [String] {
        guard id != target, order.contains(id), order.contains(target) else { return order }
        var result = order.filter { $0 != id }
        result.insert(id, at: result.firstIndex(of: target)!)
        return result
    }
}

final class PreferenceStore {
    let url: URL
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Loki/preferences.json")
    }
    func load() throws -> Preferences {
        guard FileManager.default.fileExists(atPath: url.path) else { return Preferences() }
        let state = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url))
        guard state.version == 1, !state.realms.isEmpty,
              Set(state.realms.map(\.id)).count == state.realms.count,
              state.realms.contains(where: { $0.id == state.selectedRealm }) else {
            throw NSError(domain: "Loki", code: 1, userInfo: [NSLocalizedDescriptionKey: "The saved realms could not be read. Your original file has been preserved."])
        }
        return state
    }
    func save(_ state: Preferences) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
