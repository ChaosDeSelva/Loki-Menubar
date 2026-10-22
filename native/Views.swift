import SwiftUI
import UniformTypeIdentifiers

enum LokiStyle {
    static let controlHeight: CGFloat = 36
    static let danger = Color(red: 1, green: 0.36, blue: 0.38)
    static let background = Color(red: 0.055, green: 0.075, blue: 0.065)
    static let sidebar = Color(red: 0.075, green: 0.095, blue: 0.08)
    static let surface = Color(red: 0.105, green: 0.13, blue: 0.11)
    static let muted = Color(red: 0.60, green: 0.66, blue: 0.60)
    static let text = Color(red: 0.94, green: 0.95, blue: 0.88)
}

struct LokiMark: View {
    var color: Color
    var monochrome = false
    var body: some View {
        GeometryReader { geometry in
            let paths = LokiGlyph.paths(in: CGRect(origin: .zero, size: geometry.size))
            ZStack {
                ForEach(paths.indices, id: \.self) { index in
                    Path(paths[index]).fill(index == 0
                        ? (monochrome ? color.opacity(0.35) : Color(red: 23 / 255, green: 53 / 255, blue: 40 / 255))
                        : color)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct MainView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 12) {
                    LokiMark(color: model.accent).frame(width: 33, height: 38)
                    Text("LOKI").font(.system(size: 24, weight: .black, design: .rounded)).tracking(4)
                }.padding(.top, 12)
                VStack(alignment: .leading, spacing: 5) {
                    nav("Your shelf", symbol: "square.grid.2x2", page: "shelf")
                    nav("Menu bar", symbol: "menubar.rectangle", page: "menubar")
                    nav("Groups", symbol: "folder", page: "groups")
                    nav("Realms", symbol: "circle.hexagongrid", page: "realms")
                    nav("Settings", symbol: "slider.horizontal.3", page: "settings")
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR REALMS").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(LokiStyle.muted)
                    ForEach(model.preferences.realms) { realm in
                        Button {
                            model.selectRealm(realm.id); model.page = "shelf"
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: realm.symbol).frame(width: 18)
                                Text(realm.name).lineLimit(1)
                                Spacer()
                                if realm.id == model.preferences.selectedRealm { Circle().fill(model.accent).frame(width: 5, height: 5) }
                            }
                            .foregroundStyle(realm.id == model.preferences.selectedRealm ? LokiStyle.text : LokiStyle.muted)
                            .padding(.vertical, 7)
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(model.accent).frame(width: 5, height: 5)
                    Text("ON YOUR MAC. ALWAYS.").font(.system(size: 8, weight: .semibold)).tracking(1)
                }.foregroundStyle(LokiStyle.muted)
            }
            .padding(22).frame(width: 208).background(LokiStyle.sidebar)
            Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
            Group {
                switch model.page {
                case "menubar": MenuBarView(model: model, visibility: model.visibility)
                case "groups": GroupsView(model: model).id(model.realm.id)
                case "realms": RealmsView(model: model)
                case "settings": SettingsView(model: model)
                default: ShelfView(model: model, compact: false)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(LokiStyle.background).foregroundStyle(LokiStyle.text)
        .preferredColorScheme(.dark)
        .frame(minWidth: 840, minHeight: 640)
    }
    private func nav(_ title: String, symbol: String, page: String) -> some View {
        Button { model.page = page } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 18)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
            }.padding(.horizontal, 12).padding(.vertical, 11)
                .foregroundStyle(model.page == page ? model.accent : LokiStyle.muted)
                .background(model.page == page ? model.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
}

struct ShelfView: View {
    @ObservedObject var model: AppModel
    var compact: Bool
    @FocusState private var searchFocused: Bool
    @State private var draggedID: String?
    @State private var selectedID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 16 : 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(compact ? "LOKI / \(model.realm.name.uppercased())" : "A PLACE FOR YOUR LITTLE UTILITIES")
                        .font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(model.accent)
                    if !compact {
                        Text("Less clutter. More Loki.")
                            .font(.system(size: 36, weight: .semibold, design: .rounded)).tracking(-1)
                        Text("Your favorite tools, gathered in one little shelf.")
                            .font(.system(size: 13)).foregroundStyle(LokiStyle.muted)
                    }
                }
                Spacer()
                if compact {
                    Button { (NSApp.delegate as? AppDelegate)?.showMainWindow() } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 28, height: 28)
                    }.buttonStyle(.plain).help("Open Loki window").accessibilityLabel("Open Loki window")
                    Button { (NSApp.delegate as? AppDelegate)?.closeShelf() } label: {
                        Image(systemName: "xmark").frame(width: 28, height: 28)
                    }.buttonStyle(.plain).help("Close shelf (Escape)").accessibilityLabel("Close shelf")
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(model.accent)
                TextField("Find a little mischief…", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 14)).focused($searchFocused)
                    .onSubmit {
                        if let item = model.visibleItems.first(where: { $0.id == selectedID }) ?? model.visibleItems.first { model.open(item) }
                    }
                    .onChange(of: model.query) { selectedID = nil }
                    .onMoveCommand { direction in moveSelection(direction) }
                    .accessibilityLabel("Search shelf")
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("Clear search")
                }
                Text("↵").font(.system(size: 13)).foregroundStyle(LokiStyle.muted)
            }
            .padding(14).background(LokiStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(searchFocused ? model.accent.opacity(0.45) : Color.white.opacity(0.08), lineWidth: 1))

            HStack {
                sourceButton("Apps", source: "apps", symbol: "app.dashed")
                sourceButton("Menu items", source: "menu", symbol: "menubar.rectangle")
                GroupSelector(model: model)
                Spacer()
                Button { model.favoritesOnly.toggle() } label: {
                    Image(systemName: model.favoritesOnly ? "star.fill" : "star")
                        .foregroundStyle(model.favoritesOnly ? model.accent : LokiStyle.muted).padding(6)
                }.buttonStyle(.plain).help(model.favoritesOnly ? "Show all items" : "Show favorites only")
                Button { model.refresh() } label: {
                    if model.scanning { ProgressView().controlSize(.small).frame(width: 16, height: 16) }
                    else { Image(systemName: "arrow.clockwise").frame(width: 16, height: 16) }
                }.buttonStyle(.plain).disabled(model.scanning).help("Refresh shelf").padding(6)
            }

            if let notice = model.notice {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(model.accent)
                    Text(notice).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Dismiss message")
                }.padding(12).background(model.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            if model.preferences.source == "menu" && !model.accessibility {
                PermissionCard(model: model)
                Spacer(minLength: 0)
            } else if model.visibleItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: model.scanning ? "sparkle.magnifyingglass" : "moon.stars").font(.system(size: 30)).foregroundStyle(model.accent)
                    Text(emptyTitle).font(.system(size: 17, weight: .medium, design: .rounded))
                    Text(emptyDetail).font(.system(size: 12)).foregroundStyle(LokiStyle.muted).multilineTextAlignment(.center).frame(maxWidth: 300)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.visibleItems) { item in
                            ShelfRow(item: item, model: model, selected: selectedID == item.id)
                                .onDrag { draggedID = item.id; return NSItemProvider(object: item.id as NSString) }
                                .onDrop(of: [.text], delegate: ShelfDrop(target: item.id, dragged: $draggedID, model: model))
                        }
                    }.padding(1)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).layoutPriority(-1).scrollIndicators(.automatic)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle().fill(model.scanning ? Color.orange : model.accent).frame(width: 5, height: 5)
                    Text(model.scanning ? "Gathering your tools…" : model.scanSummary).font(.system(size: 10)).lineLimit(1)
                    Spacer()
                    if compact {
                        Menu(model.realm.name) {
                            ForEach(model.preferences.realms) { realm in Button(realm.name) { model.selectRealm(realm.id) } }
                            Divider()
                            Button("Quit Loki") { NSApp.terminate(nil) }
                        }.menuStyle(.borderlessButton).fixedSize().font(.system(size: 11))
                    } else { Text("\(model.realm.pins.count) favorites in \(model.realm.name)").font(.system(size: 10)) }
                }.foregroundStyle(LokiStyle.muted)

            }
        }
        .padding(compact ? 24 : 30)
        .background { if !compact { LokiStyle.background } }
        .foregroundStyle(LokiStyle.text).preferredColorScheme(.dark)
        .onExitCommand { if compact { (NSApp.delegate as? AppDelegate)?.closeShelf() } }
        .onAppear { searchFocused = true; model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .lokiFocusSearch)) { _ in searchFocused = true }
    }
    private var emptyTitle: String {
        if model.scanning { return "Looking around the realm…" }
        if !model.query.isEmpty { return "No mischief by that name." }
        return model.favoritesOnly ? "Your favorites start here." : "Nothing on the shelf yet."
    }
    private var emptyDetail: String {
        if !model.query.isEmpty { return "Try another name, or clear the search." }
        if model.favoritesOnly { return "Turn off the star filter, then star a tool to keep it close." }
        return model.preferences.source == "menu" ? "Refresh to scan again. Some macOS items do not expose accessible controls." : "Open an app and it will appear here."
    }
    private func moveSelection(_ direction: MoveCommandDirection) {
        let items = model.visibleItems
        guard !items.isEmpty, direction == .down || direction == .up else { return }
        let index = items.firstIndex(where: { $0.id == selectedID }) ?? (direction == .down ? -1 : items.count)
        selectedID = items[max(0, min(items.count - 1, index + (direction == .down ? 1 : -1)))].id
    }
    private func sourceButton(_ title: String, source: String, symbol: String) -> some View {
        Button { model.source(source) } label: {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 11).padding(.vertical, 7)
                .foregroundStyle(model.preferences.source == source ? model.accent : LokiStyle.muted)
                .background(model.preferences.source == source ? model.accent.opacity(0.09) : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }
}

struct ShelfRow: View {
    let item: ShelfItem
    @ObservedObject var model: AppModel
    var selected: Bool
    @State private var hover = false
    var body: some View {
        HStack(spacing: 0) {
            Button { model.open(item) } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04))
                        if let icon = item.icon { Image(nsImage: icon).resizable().interpolation(.high).frame(width: 29, height: 29) }
                        else { Image(systemName: symbol).font(.system(size: 21)).foregroundStyle(model.accent) }
                    }.frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(item.kind == .app ? "Open application" : item.appName).font(.system(size: 10)).foregroundStyle(LokiStyle.muted).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if hover || selected { Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(model.accent).padding(.trailing, 12) }
                }.padding(.leading, 12).padding(.vertical, 10).contentShape(Rectangle())
            }.buttonStyle(.plain).help(item.kind == .app ? "Bring \(item.title) forward" : "Open \(item.title) menu")
            Button { model.pin(item.id) } label: {
                Image(systemName: model.realm.pins.contains(item.id) ? "star.fill" : "star")
                    .font(.system(size: 12)).foregroundStyle(model.realm.pins.contains(item.id) ? model.accent : LokiStyle.muted.opacity(0.55))
                    .frame(width: 42, height: 48).contentShape(Rectangle())
            }.buttonStyle(.plain).help(model.realm.pins.contains(item.id) ? "Unpin \(item.title)" : "Pin \(item.title)")
        }
        .background(hover || selected ? model.accent.opacity(0.07) : LokiStyle.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? model.accent.opacity(0.55) : Color.white.opacity(hover ? 0.09 : 0.035), lineWidth: 1))
        .onHover { hover = $0 }
        .contextMenu {
            Button("Open \(item.title)") { model.open(item) }
            Button(model.realm.pins.contains(item.id) ? "Remove from favorites" : "Add to favorites") { model.pin(item.id) }
            Menu("Group") {
                ForEach(model.realm.availableGroups + ["Ungrouped"], id: \.self) { group in
                    Button(group) { model.group(item.id, name: group) }
                }
            }
            Button("Move to top of shelf") {
                if let first = model.visibleItems.first { model.reorder(item.id, before: first.id) }
            }
        }
    }
    private var symbol: String {
        let title = item.title.lowercased()
        if title.contains("wi-fi") || title.contains("wifi") { return "wifi" }
        if title.contains("battery") { return "battery.100percent" }
        if title.contains("clock") || title.contains("date") { return "clock" }
        if title.contains("sound") || title.contains("volume") { return "speaker.wave.2" }
        if title.contains("bluetooth") { return "antenna.radiowaves.left.and.right" }
        return "menubar.rectangle"
    }
}

struct ShelfDrop: DropDelegate {
    let target: String
    @Binding var dragged: String?
    let model: AppModel
    func validateDrop(info: DropInfo) -> Bool { dragged != nil && model.query.isEmpty && !model.favoritesOnly }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard let dragged else { return false }
        model.reorder(dragged, before: target)
        self.dragged = nil
        return true
    }
}

struct PermissionCard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "hand.raised.fingers.spread").font(.system(size: 25)).foregroundStyle(model.accent)
            Text("Let Loki lend a hand.").font(.system(size: 21, weight: .semibold, design: .rounded))
            Text("Accessibility lets Loki find menu bar items and open their menus when you choose one. Your data stays on this Mac.")
                .font(.system(size: 12)).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                Text("No screen recording. No account. No tracking.")
            }.font(.system(size: 10)).foregroundStyle(model.accent)
            Button("Allow Accessibility →") { model.requestAccessibility() }
                .buttonStyle(AccentButton(color: model.accent))
            Button("Already allowed? Check again") { model.refresh() }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(LokiStyle.muted)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(LokiStyle.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct AccentButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 16).frame(height: LokiStyle.controlHeight)
            .foregroundStyle(LokiStyle.background).background(color.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 8))
            .opacity(enabled ? 1 : 0.4)
    }
}

struct RealmsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("A realm for every mood.").font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(-0.8)
            Text("Each realm remembers its own favorites and shelf order. Switch whenever your day changes.")
                .font(.system(size: 13)).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
            ForEach(model.preferences.realms) { realm in
                RealmCard(realm: realm, model: model)
            }
            Text("These profiles arrange Loki’s shelf. They do not move or hide the system menu bar.")
                .font(.system(size: 11)).foregroundStyle(LokiStyle.muted)
            Spacer()
        }.padding(30)
    }
}

struct RealmCard: View {
    let realm: Realm
    @ObservedObject var model: AppModel
    @State private var editing = false
    @State private var name = ""
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: realm.symbol).font(.system(size: 24)).foregroundStyle(model.accent).frame(width: 42)
            VStack(alignment: .leading, spacing: 6) {
                if editing {
                    TextField("Realm name", text: $name).textFieldStyle(LokiTextFieldStyle()).onSubmit { model.renameRealm(realm.id, name: name); editing = false }
                } else { Text(realm.name).font(.system(size: 17, weight: .medium, design: .rounded)) }
                Text("\(realm.pins.count) favorites · your own little world").font(.system(size: 11)).foregroundStyle(LokiStyle.muted)
            }
            Spacer()
            Button { if editing { model.renameRealm(realm.id, name: name) }; name = realm.name; editing.toggle() } label: { Image(systemName: editing ? "checkmark" : "pencil") }
                .buttonStyle(.plain).help(editing ? "Save realm name" : "Rename realm")
            Button(realm.id == model.preferences.selectedRealm ? "Active" : "Enter") { model.selectRealm(realm.id) }
                .buttonStyle(AccentButton(color: model.accent)).disabled(realm.id == model.preferences.selectedRealm)
        }.padding(20).background(LokiStyle.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                Text("Make a little mischief.").font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(-0.8)
                settingsGroup("PERSONALITY") {
                    HStack {
                        Text("A color for your realm").font(.system(size: 13))
                        Spacer()
                        ForEach(["moss", "ember", "frost"], id: \.self) { accent in
                            Button { model.preferences.accent = accent; model.save() } label: {
                                Circle().fill(color(accent)).frame(width: 22, height: 22)
                                    .overlay(Circle().stroke(Color.white, lineWidth: model.preferences.accent == accent ? 2 : 0).padding(-3))
                                    .padding(4)
                            }.buttonStyle(.plain).help(accent.capitalized)
                        }
                    }
                    Toggle("A little extra personality", isOn: Binding(get: { model.preferences.playful }, set: { model.preferences.playful = $0; model.save() }))
                        .toggleStyle(.switch).tint(model.accent).font(.system(size: 13))
                    Text("Playful copy for your shelf.").font(.system(size: 11)).foregroundStyle(LokiStyle.muted)
                }
                settingsGroup("AT YOUR SERVICE") {
                    Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                        .toggleStyle(.switch).tint(model.accent).font(.system(size: 13))
                    HStack { Text("Summon shortcut"); Spacer(); Text("Control + Option + L").foregroundStyle(model.accent) }.font(.system(size: 12))
                    HStack { Text("Accessibility"); Spacer(); Text(model.accessibility ? "Allowed" : "Not allowed").foregroundStyle(model.accessibility ? model.accent : LokiStyle.muted) }.font(.system(size: 12))
                    if !model.accessibility {
                        Button("Allow menu access") { model.requestAccessibility() }.buttonStyle(AccentButton(color: model.accent))
                    }
                }
                UpdateSettingsView(updater: model.updater, accent: model.accent)
                settingsGroup("HONEST LITTLE UTILITY") {
                    Label("Local by design", systemImage: "lock.shield").font(.system(size: 13, weight: .medium)).foregroundStyle(model.accent)
                    Text("Loki stores your realms on this Mac. It has no analytics, cloud service, or screen capture. Menu discovery uses Accessibility only when you select Menu items.")
                        .font(.system(size: 12)).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
                    Text("Icon hiding uses a menu-bar divider. Set it up in Menu bar. Hover near the menu bar to reveal; display changes and quitting Loki restore all icons.")
                        .font(.system(size: 12)).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
                    Button("Open settings folder") { model.openSettingsFolder() }.buttonStyle(.plain).foregroundStyle(model.accent).font(.system(size: 12))
                }
                if let notice = model.notice { Text(notice).font(.system(size: 12)).foregroundStyle(model.accent) }
                HStack {
                    Text("LOKI 0.1.0 · NATIVE SWIFT").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(LokiStyle.muted)
                    Spacer()
                    Button("Quit Loki") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(LokiStyle.muted)
                }
            }.padding(30)
        }.scrollIndicators(.hidden)
    }
    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(LokiStyle.muted)
            content()
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(LokiStyle.surface, in: RoundedRectangle(cornerRadius: 14))
    }
    private func color(_ name: String) -> Color {
        switch name {
        case "ember": return Color(red: 1, green: 0.62, blue: 0.39)
        case "frost": return Color(red: 0.58, green: 0.79, blue: 0.98)
        default: return Color(red: 0.76, green: 0.9, blue: 0.52)
        }
    }
}

extension Notification.Name { static let lokiFocusSearch = Notification.Name("LokiFocusSearch") }

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var visibility: VisibilityController
    @State private var confirmStop = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Room for a little mischief.").font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(-0.8)
                Text("Keep everyday icons in sight. Tuck the rest behind a divider.")
                    .foregroundStyle(LokiStyle.muted)
                VStack(alignment: .leading, spacing: 16) {
                    Label("Set up your menu bar", systemImage: "menubar.rectangle").font(.headline)
                    if visibility.supported {
                    Text("1. Show the divider.\n2. Hold Command and drag the filter-shaped divider to the left of Loki’s icon.\n3. Command-drag the icons you want to hide to the left of the divider.\n4. Choose Tuck icons, close this window, and move the pointer away from the menu bar.")
                        .font(.system(size: 13)).lineSpacing(7).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Loki’s divider cannot hide icons on macOS 27 yet. The previous build incorrectly reported success. Use macOS’s menu-bar settings for now; Loki’s searchable shelf and groups remain available.")
                            .font(.system(size: 13)).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        if !visibility.supported {
                            Button("Open macOS Menu Bar settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!)
                            }.buttonStyle(AccentButton(color: model.accent))
                        } else if visibility.managing {
                            Button("Tuck icons") { visibility.tuck(); (NSApp.delegate as? AppDelegate)?.hideWindows() }
                                .buttonStyle(AccentButton(color: model.accent))
                            Button("Stop hiding & remove divider") { confirmStop = true }.buttonStyle(DestructiveButton())
                        } else {
                            Button("Show divider") { model.startVisibility() }.buttonStyle(AccentButton(color: model.accent))
                        }
                    }
                    Text(visibility.concealed ? "Hiding requested" : visibility.managing ? "Divider ready · icons revealed" : "All icons visible")
                        .font(.caption).foregroundStyle(model.accent)
                    if let failure = visibility.failure { Text(failure).font(.caption).foregroundStyle(.orange) }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(LokiStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                if visibility.supported {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Rehide after hovering away", isOn: Binding(get: { model.preferences.autoRehide ?? true }, set: { model.preferences.autoRehide = $0; model.save(); visibility.stop() }))
                        .toggleStyle(.switch).tint(model.accent)
                    HStack {
                        Text("Delay")
                        Slider(value: Binding(get: { model.preferences.rehideDelay ?? 3 }, set: { model.preferences.rehideDelay = $0; model.save(); visibility.stop() }), in: 1...15, step: 1)
                        Text("\(Int(model.preferences.rehideDelay ?? 3))s").monospacedDigit().frame(width: 30)
                    }
                    Text("Hover near the menu bar to reveal. Loki stays revealed while its window is active. Quitting or changing displays stops hiding; changing Spaces reveals icons. Setup is never enabled automatically at launch.")
                        .font(.caption).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
                }.padding(20).background(LokiStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                }
                Text("Compatibility preview: macOS controls placement and some system icons cannot be moved. A crowded or notched display may still need the searchable shelf. No screen capture or private system APIs are used.")
                    .font(.caption).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
            }.padding(30)
        }
        .alert("Stop hiding and remove the divider?", isPresented: $confirmStop) {
            Button("Cancel", role: .cancel) { }
            Button("Stop hiding", role: .destructive) { visibility.stop() }
        } message: { Text("All icons will be revealed. You can set up the divider again later.") }
    }
}

struct GroupsView: View {
    @ObservedObject var model: AppModel
    @State private var newName = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your groups. Your names.").font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(-0.8)
                Text("Organize \(model.realm.name) your way: Work · Development, Work · Meetings, Creative, Home—or anything that fits your day.")
                    .font(.system(size: 13)).foregroundStyle(LokiStyle.muted)
                HStack {
                    TextField("New group name", text: $newName).textFieldStyle(LokiTextFieldStyle())
                        .onSubmit { addGroup() }.accessibilityLabel("New group name")
                    Button("Add group", action: addGroup).buttonStyle(AccentButton(color: model.accent))
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let notice = model.notice { Text(notice).font(.caption).foregroundStyle(model.accent) }
                if model.canUndoGroupDeletion {
                    Button("Undo last group deletion") { model.undoGroupDeletion() }
                        .buttonStyle(AccentButton(color: model.accent))
                }
                if model.realm.availableGroups.isEmpty {
                    Text("No groups yet. Add your first one above.").foregroundStyle(LokiStyle.muted)
                }
                ForEach(model.realm.availableGroups, id: \.self) { name in
                    GroupEditorRow(name: name, model: model)
                }
                Text("Right-click a shelf item → Group to assign it. Rename keeps assignments, including items that are currently offline. Removing a group returns its items to Ungrouped; it never removes apps, favorites, or shelf entries. Groups are independent in each realm.")
                    .font(.caption).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
            }.padding(30)
        }
    }
    private func addGroup() { if model.setGroupName(newName) { newName = "" } }
}

struct GroupEditorRow: View {
    let name: String
    @ObservedObject var model: AppModel
    @State private var draft: String
    @State private var confirmDelete = false
    init(name: String, model: AppModel) {
        self.name = name; self.model = model; _draft = State(initialValue: name)
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "folder").foregroundStyle(model.accent).frame(width: 24, height: LokiStyle.controlHeight)
            VStack(alignment: .leading, spacing: 5) {
                TextField("Group name", text: $draft).textFieldStyle(LokiTextFieldStyle())
                    .onSubmit { model.setGroupName(draft, replacing: name) }
                    .accessibilityLabel("Rename \(name)")
                Text("\((model.realm.groups ?? [:]).values.filter { $0 == name }.count) assigned items")
                    .font(.caption).foregroundStyle(LokiStyle.muted)
            }
            Button("Save") { model.setGroupName(draft, replacing: name) }.buttonStyle(AccentButton(color: model.accent)).disabled(draft == name)
            Button { confirmDelete = true } label: { Image(systemName: "trash") }
                .buttonStyle(DestructiveButton()).help("Remove \(name); its items become Ungrouped")
                .accessibilityLabel("Remove \(name)")
        }.padding(16).background(LokiStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        .alert("Delete “\(name)”?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete group", role: .destructive) { model.removeGroup(name) }
        } message: { Text("Its items will move to Ungrouped. Apps and favorites will stay. You can undo this deletion in Groups.") }
    }
}

struct LokiTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.plain).font(.system(size: 13))
            .padding(.horizontal, 12).frame(height: LokiStyle.controlHeight)
            .background(LokiStyle.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12)))
    }
}

struct DestructiveButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14).frame(height: LokiStyle.controlHeight)
            .foregroundStyle(LokiStyle.danger)
            .background(LokiStyle.danger.opacity(configuration.isPressed ? 0.25 : 0.12), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(LokiStyle.danger.opacity(0.25)))
            .opacity(enabled ? 1 : 0.4)
    }
}

struct GroupSelector: View {
    @ObservedObject var model: AppModel
    @State private var showing = false
    var body: some View {
        Button { showing.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder")
                Text(model.selectedGroup == "All" ? "Groups" : model.selectedGroup).lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }.font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 7)
                .foregroundStyle(model.selectedGroup == "All" ? LokiStyle.muted : model.accent)
                .background(model.selectedGroup == "All" ? LokiStyle.surface : model.accent.opacity(0.09), in: Capsule())
        }.buttonStyle(.plain).frame(maxWidth: 122)
            .accessibilityLabel("Group filter: \(model.selectedGroup)")
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(["All"] + model.realm.availableGroups + ["Ungrouped"], id: \.self) { name in
                                Button { model.selectedGroup = name; showing = false } label: {
                                    HStack {
                                        Text(name).lineLimit(2).multilineTextAlignment(.leading)
                                        Spacer(minLength: 8)
                                        if model.selectedGroup == name { Image(systemName: "checkmark").foregroundStyle(model.accent) }
                                    }.font(.system(size: 12)).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                        .background(model.selectedGroup == name ? model.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7))
                                }.buttonStyle(.plain)
                            }
                        }
                    }.frame(maxHeight: 260)
                    Divider()
                    Button { showing = false; model.page = "groups"; (NSApp.delegate as? AppDelegate)?.showMainWindow() } label: {
                        Label("Manage groups…", systemImage: "slider.horizontal.3").font(.system(size: 12)).padding(10)
                    }.buttonStyle(.plain).foregroundStyle(model.accent)
                }.padding(8).frame(width: 240).foregroundStyle(LokiStyle.text).preferredColorScheme(.dark)
            }
    }
}

struct UpdateSettingsView: View {
    @ObservedObject var updater: UpdateController
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("UPDATES").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(LokiStyle.muted)
            Toggle("Check for updates automatically", isOn: Binding(get: { updater.automaticChecks }, set: updater.setAutomaticChecks))
                .toggleStyle(.switch).tint(accent)
            Text("Updates are downloaded and verified before installation. Loki will ask before installing and relaunching. Checks contact the public update feed on GitHub; no shelf or group data is sent.")
                .font(.system(size: 12)).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
            Button("Check for updates…") { updater.checkForUpdates() }
                .buttonStyle(AccentButton(color: accent)).disabled(!updater.canCheck)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(LokiStyle.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}
