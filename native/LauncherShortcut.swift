import AppKit
import SwiftUI
import Carbon

@MainActor
enum LauncherHotKey {
    static func matches(_ event: NSEvent, shortcut: LaunchShortcut) -> Bool {
        let flags = event.modifierFlags
        let modifiers = (flags.contains(.command) ? UInt32(cmdKey) : 0) |
            (flags.contains(.control) ? UInt32(controlKey) : 0) |
            (flags.contains(.option) ? UInt32(optionKey) : 0) |
            (flags.contains(.shift) ? UInt32(shiftKey) : 0)
        return UInt32(event.keyCode) == shortcut.keyCode && modifiers == shortcut.modifiers
    }
    static func conflict(_ shortcut: LaunchShortcut) -> String? {
        guard shortcut.isValid else { return "Use Shift-Space, or include Command or Control." }
        if shortcut.keyCode == UInt32(kVK_ANSI_L), shortcut.modifiers == UInt32(controlKey | optionKey) {
            return "⌃⌥L opens Loki’s shelf. Choose a different shortcut for the launcher."
        }
        var shortcuts: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&shortcuts) == noErr, let items = shortcuts?.takeRetainedValue() as? [[String: Any]] else {
            return "Could not check macOS shortcuts. Try again before saving."
        }
        if items.contains(where: {
            ($0[kHISymbolicHotKeyEnabled] as? NSNumber)?.boolValue == true &&
            ($0[kHISymbolicHotKeyCode] as? NSNumber)?.uint32Value == shortcut.keyCode &&
            ($0[kHISymbolicHotKeyModifiers] as? NSNumber)?.uint32Value == shortcut.modifiers
        }) {
            let purpose = shortcut.keyCode == 49 && shortcut.modifiers == UInt32(cmdKey | optionKey) ? "Finder search" : "a macOS shortcut"
            return "\(shortcut.label) is assigned to \(purpose). Choose another combination, or change that assignment in System Settings → Keyboard → Keyboard Shortcuts first."
        }
        return nil
    }
    static func register(_ shortcut: LaunchShortcut, reference: inout EventHotKeyRef?) -> OSStatus {
        RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x4c4f4b49, id: 2),
            GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &reference)
    }
    static func unavailable(_ shortcut: LaunchShortcut) -> String {
        "\(shortcut.label) is used by another app or unavailable. Your previous shortcut is unchanged. Choose another combination."
    }
}

struct LauncherShortcutPicker: View {
    @ObservedObject var model: LauncherModel
    @State private var showing = false
    @State private var code: UInt32 = 49
    @State private var command = true
    @State private var control = false
    @State private var option = false
    @State private var shift = true
    private static let keys: [(code: UInt32, label: String)] = [
        (49, "Space"), (36, "Return"), (48, "Tab"), (51, "Delete"),
        (0, "A"), (11, "B"), (8, "C"), (2, "D"), (14, "E"), (3, "F"), (5, "G"), (4, "H"),
        (34, "I"), (38, "J"), (40, "K"), (37, "L"), (46, "M"), (45, "N"), (31, "O"), (35, "P"),
        (12, "Q"), (15, "R"), (1, "S"), (17, "T"), (32, "U"), (9, "V"), (13, "W"), (7, "X"), (16, "Y"), (6, "Z"),
        (29, "0"), (18, "1"), (19, "2"), (20, "3"), (21, "4"), (23, "5"), (22, "6"), (26, "7"), (28, "8"), (25, "9"),
        (24, "="), (27, "−"), (30, "]"), (33, "["), (39, "'"), (41, ";"), (42, "\\"), (43, ","), (44, "/"), (47, "."), (50, "`"),
        (123, "←"), (124, "→"), (125, "↓"), (126, "↑"),
        (122, "F1"), (120, "F2"), (99, "F3"), (118, "F4"), (96, "F5"), (97, "F6"),
        (98, "F7"), (100, "F8"), (101, "F9"), (109, "F10"), (103, "F11"), (111, "F12"),
        (105, "F13"), (107, "F14"), (113, "F15"), (106, "F16"), (64, "F17"), (79, "F18"), (80, "F19"), (90, "F20")
    ]
    private var candidate: LaunchShortcut {
        LaunchShortcut(keyCode: code, modifiers: (command ? UInt32(cmdKey) : 0) | (control ? UInt32(controlKey) : 0) |
            (option ? UInt32(optionKey) : 0) | (shift ? UInt32(shiftKey) : 0),
            keyLabel: Self.keys.first(where: { $0.code == code })?.label ?? model.settings.shortcut.keyLabel)
    }
    var body: some View {
        Button(model.settings.shortcut.label) {
            let value = model.settings.shortcut
            code = value.keyCode
            command = value.modifiers & UInt32(cmdKey) != 0; control = value.modifiers & UInt32(controlKey) != 0
            option = value.modifiers & UInt32(optionKey) != 0; shift = value.modifiers & UInt32(shiftKey) != 0
            model.shortcutError = nil; showing = true
        }
        .accessibilityLabel("Change launcher shortcut")
        .popover(isPresented: $showing) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Launcher shortcut").font(.headline)
                HStack {
                    Toggle("⌃ Control", isOn: $control)
                    Toggle("⌥ Option", isOn: $option)
                }
                HStack {
                    Toggle("⇧ Shift", isOn: $shift)
                    Toggle("⌘ Command", isOn: $command)
                }
                Picker("Key", selection: $code) {
                    ForEach(Self.keys, id: \.code) { Text($0.label).tag($0.code) }
                }
                Text(candidate.label).font(.system(size: 20, weight: .medium)).frame(maxWidth: .infinity)
                if let error = model.shortcutError ?? model.settingsError {
                    Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Text("Choose modifiers and a key here; you don’t need to press the shortcut while editing.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancel") { showing = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Save shortcut") { if model.setShortcut(candidate) { showing = false } }
                        .disabled(!candidate.isValid).keyboardShortcut(.defaultAction)
                }
            }.toggleStyle(.checkbox).padding(20).frame(width: 330).preferredColorScheme(.dark)
        }
    }
}
