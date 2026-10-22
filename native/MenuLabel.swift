import Foundation

/// Resolves system extras without mistaking their shared host label for an item name.
enum MenuLabel {
    static func resolve(identifier: String, title: String, description: String, help: String, owner: String, system: Bool) -> String? {
        let generic = ["control center", "control centre", "menubaragent", "menu bar", "menu extra", "status item"]
        let candidates = [title, description, help].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let specific = candidates.first(where: { !$0.isEmpty && !generic.contains($0.lowercased()) })
        guard system else { return specific.map { String($0.prefix(100)) } ?? owner }
        let token = identifier.lowercased().filter { $0.isLetter || $0.isNumber }
        let labels: [(String, String)] = [
            ("screenmirroring", "Screen Mirroring"), ("nowplaying", "Now Playing"),
            ("fastuserswitch", "User Switching"), ("keyboardbrightness", "Keyboard Brightness"),
            ("accessibility", "Accessibility"), ("bluetooth", "Bluetooth"), ("wifi", "Wi-Fi"),
            ("battery", "Battery"), ("volume", "Sound"), ("sound", "Sound"),
            ("display", "Displays"), ("focus", "Focus"), ("donotdisturb", "Focus"),
            ("clock", "Clock"), ("siri", "Siri"), ("spotlight", "Spotlight"),
            ("timemachine", "Time Machine"), ("vpn", "VPN"), ("controlcenter", "Control Center")
        ]
        if let match = labels.dropLast().first(where: { token.contains($0.0) }) { return match.1 }
        if let specific { return String(specific.prefix(100)) }
        if token == "controlcenter" || token == "comapplecontrolcenter" { return "Control Center" }
        // Do not invent labels for unidentified system proxies. One real Control
        // Center entry is retained by the caller; blank proxies are omitted.
        return candidates.contains(where: { $0.lowercased() == "control center" }) ? "Control Center" : nil
    }
    static func systemID(identifier: String, title: String) -> String {
        let label = resolve(identifier: identifier, title: title, description: "", help: "", owner: "", system: true) ?? title
        let token = label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isLetter || $0.isNumber }
        return "menu:system:" + token
    }

    static func migratedID(_ id: String) -> String {
        let parts = id.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == "menu",
              ["com.apple.MenuBarAgent", "com.apple.controlcenter", "com.apple.systemuiserver"].contains(parts[1]),
              let label = resolve(identifier: parts[2], title: "", description: "", help: "", owner: "", system: true) else { return id }
        return systemID(identifier: parts[2], title: label)
    }
}

/// Titles are presentation, never persistence keys. Unidentified extras use their
/// owner's traversal slot; apps that reorder indistinguishable extras remain ambiguous.
enum MenuIdentity {
    static func nextOccurrence(identifier: String, title: String, counters: inout [String: Int]) -> Int {
        let key = identifier.isEmpty ? "title:" + title : "identifier:" + identifier
        let occurrence = counters[key, default: 0]
        counters[key] = occurrence + 1
        return occurrence
    }

    static func thirdParty(bundle: String, identifier: String, slot: Int) -> String {
        identifier.isEmpty ? "menu-slot:\(bundle):\(slot)" : "menu:\(bundle):\(identifier)"
    }
}
