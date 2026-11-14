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
                TextField(model.preferences.playful ? "Find a little mischief…" : "Search your shelf…", text: $model.query)
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
                ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.visibleItems) { item in
                            ShelfRow(item: item, model: model, selected: selectedID == item.id)
                                .id(item.id)
                                .onDrag { draggedID = item.id; return NSItemProvider(object: item.id as NSString) }
                                .onDrop(of: [.text], delegate: ShelfDrop(target: item.id, dragged: $draggedID, model: model))
                        }
                    }.padding(1)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).layoutPriority(-1).scrollIndicators(.automatic)
                .onChange(of: selectedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle().fill(model.scanning ? Color.orange : model.accent).frame(width: 5, height: 5)
                    Text(model.scanning ? (model.preferences.playful ? "Gathering your tools…" : "Refreshing…") : model.scanSummary).font(.system(size: 10)).lineLimit(1)
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
        if model.scanning { return model.preferences.playful ? "Looking around the realm…" : "Finding menu items…" }
        if !model.query.isEmpty { return model.preferences.playful ? "No mischief by that name." : "No matching items." }
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
                Text(model.preferences.playful ? "Make a little mischief." : "Settings").font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(-0.8)
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
                        .toggleStyle(.switch).tint(model.accent).font(.system(size: 13)).disabled(model.policy.launchAtLogin != nil)
                    if model.policy.launchAtLogin != nil { ManagedCaption() }
                    HStack { Text("Summon shortcut"); Spacer(); Text("Control + Option + L").foregroundStyle(model.accent) }.font(.system(size: 12))
                    HStack { Text("Accessibility"); Spacer(); Text(model.accessibility ? "Allowed" : "Not allowed").foregroundStyle(model.accessibility ? model.accent : LokiStyle.muted) }.font(.system(size: 12))
                    if !model.accessibility {
                        Button("Allow menu access") { model.requestAccessibility() }.buttonStyle(AccentButton(color: model.accent))
                    }
                }
                UpdateSettingsView(updater: model.updater, policy: model.policy, accent: model.accent)
                settingsGroup("HONEST LITTLE UTILITY") {
                    Label("Local by design", systemImage: "lock.shield").font(.system(size: 13, weight: .medium)).foregroundStyle(model.accent)
                    Text("Loki stores your realms on this Mac. It has no analytics, cloud service, or screen capture. Menu discovery uses Accessibility only when you select Menu items.")
                        .font(.system(size: 12)).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
                    Text("Choose icons to hide in Menu bar. Loki moves them behind a divider using public macOS interfaces. Quitting Loki shows every icon again.")
                        .font(.system(size: 12)).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
                    Button("Open settings folder") { model.openSettingsFolder() }.buttonStyle(.plain).foregroundStyle(model.accent).font(.system(size: 12))
                }
                if let notice = model.notice { Text(notice).font(.system(size: 12)).foregroundStyle(model.accent) }
                HStack {
                    Text("LOKI \(lokiVersion.uppercased()) · NATIVE SWIFT").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(LokiStyle.muted)
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
    @State private var filter = ""

    private typealias Candidate = (id: String, title: String, owner: String, running: Bool)

    /// One allowlist toggle: macOS 27 hides every icon an app shows, so the app is the unit.
    private struct AppRow: Identifiable {
        let id: String
        let name: String
        let itemIDs: [String]
        let titles: [String]
        let running: Bool
    }

    private static let menuBarSettingsURL = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MENU BAR").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(model.accent)
                    Text("Room for a little mischief.").font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(-0.8)
                    Text(intro).font(.system(size: 13)).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
                }
                if visibility.backend == .unavailable {
                    unavailableCard
                } else {
                    hiddenIconsCard
                    gettingThereCard
                }
                Text(footer).font(.caption).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
            }.padding(30)
        }
        .scrollIndicators(.hidden)
        .onAppear { model.refreshExtras() }
    }

    // MARK: Cards

    private var hiddenIconsCard: some View {
        card {
            HStack(alignment: .center) {
                Label("Hidden icons", systemImage: "eye.slash").font(.headline)
                Spacer()
                statusPill
            }
            backendNote
            if !model.accessibility {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Loki needs Accessibility to list your menu-bar icons\(visibility.usesAllowlist ? "" : " and move them").")
                        .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    Button("Allow Accessibility") { model.requestAccessibility() }.buttonStyle(AccentButton(color: model.accent))
                }
            } else {
                TextField(visibility.usesAllowlist ? "Filter apps" : "Filter icons", text: $filter)
                    .textFieldStyle(LokiTextFieldStyle()).accessibilityLabel(visibility.usesAllowlist ? "Filter apps" : "Filter icons")
                checklist
                if listLocked { ManagedCaption(model.policy.disableHiding ? "Icon hiding is turned off by your organization" : nil) }
                HStack(spacing: 14) {
                    Button(visibility.arranging ? "Moving icons…" : "Apply") { model.applyHiding() }
                        .buttonStyle(AccentButton(color: model.accent))
                        .disabled(visibility.arranging || model.policy.disableHiding)
                        .help(visibility.usesAllowlist ? "Hide the chosen apps’ icons" : "Move the chosen icons behind Loki’s divider")
                    textButton("Refresh list", symbol: "arrow.clockwise", enabled: !visibility.arranging) { model.refreshExtras() }
                    Spacer()
                    textButton("Reveal all", symbol: "eye", enabled: visibility.mode != .idle && !visibility.arranging) { visibility.revealAll() }
                        .help("Show every icon and stop hiding until you choose Apply")
                }
            }
            if let summary = visibility.summary {
                Label(summary, systemImage: "checkmark.circle").font(.caption).foregroundStyle(LokiStyle.muted)
            }
            if let failure = visibility.failure {
                Label(failure, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var unavailableCard: some View {
        card {
            HStack(alignment: .center) {
                Label("Hidden icons", systemImage: "eye.slash").font(.headline)
                Spacer()
                pill("Not available", color: LokiStyle.muted, busy: false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Hiding status: not available on this macOS build")
            }
            Text("Icons can’t be hidden on this macOS build. macOS keeps every menu-bar icon on screen and does not give Loki a way to tuck any of them away, so every icon stays visible.")
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Text("You can still choose which of Apple’s controls appear in the menu bar from macOS settings. Loki’s shelf keeps working for every icon.")
                .font(.caption).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
            Button("Open macOS Menu Bar settings") { NSWorkspace.shared.open(Self.menuBarSettingsURL) }
                .buttonStyle(AccentButton(color: model.accent))
            if let failure = visibility.failure {
                Label(failure, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var gettingThereCard: some View {
        card {
            Label("Getting to hidden icons", systemImage: "hand.point.up.left").font(.headline)
            Text(gettingThere).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Toggle("Show hidden icons when the pointer touches the menu bar", isOn: setting(\.hoverReveal, default: false))
                .toggleStyle(.switch).tint(model.accent).font(.system(size: 13))
                .disabled(model.policy.hoverReveal != nil)
                .accessibilityLabel("Show hidden icons when the pointer touches the menu bar")
            if model.policy.hoverReveal != nil { ManagedCaption() }
            Toggle("Hide them again after the pointer leaves", isOn: setting(\.autoRehide, default: true))
                .toggleStyle(.switch).tint(model.accent).font(.system(size: 13))
                .disabled(model.policy.autoRehide != nil)
                .accessibilityLabel("Hide icons again after the pointer leaves the menu bar")
            if model.policy.autoRehide != nil { ManagedCaption() }
            HStack(spacing: 12) {
                Text("Delay").font(.system(size: 13))
                Slider(value: Binding(get: { delay }, set: { model.preferences.rehideDelay = $0; model.save(); model.applyHidingSettings() }),
                       in: delayRange, step: 1)
                    .tint(model.accent)
                    .disabled(model.policy.rehideDelay != nil || !autoRehideOn)
                    .accessibilityLabel("Delay before hiding again")
                    .accessibilityValue("\(Int(delay)) seconds")
                Text("\(Int(delay))s").font(.system(size: 12)).monospacedDigit().foregroundStyle(model.accent).frame(width: 30, alignment: .trailing)
                    .accessibilityHidden(true)
            }.opacity(autoRehideOn ? 1 : 0.5)
            if model.policy.rehideDelay != nil { ManagedCaption() }
        }
    }

    // MARK: Checklist

    @ViewBuilder private var checklist: some View {
        let empty = visibility.usesAllowlist ? appRows.isEmpty : iconRows.isEmpty
        if empty {
            Text(emptyText).font(.caption).foregroundStyle(LokiStyle.muted).padding(.vertical, 4)
        } else {
            VStack(spacing: 0) {
                if visibility.usesAllowlist {
                    ForEach(Array(appRows.enumerated()), id: \.element.id) { index, app in
                        if index > 0 { rowDivider }
                        appToggle(app)
                    }
                } else {
                    ForEach(Array(iconRows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { rowDivider }
                        iconToggle(row)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
            .background(LokiStyle.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06)))
            .disabled(visibility.arranging || listLocked)
        }
    }

    private func iconToggle(_ row: Candidate) -> some View {
        let isOn = Binding(get: { isHidden(row.id) }, set: { model.setHidden(row.id, hidden: $0) })
        return Toggle(isOn: isOn) {
            rowLabel(title: row.title, caption: row.owner, running: row.running)
        }
        .toggleStyle(.switch).tint(model.accent).padding(.vertical, 9)
        .accessibilityLabel("Hide \(row.title)")
        .accessibilityHint(row.running ? "From \(row.owner)" : "Not running")
    }

    private func appToggle(_ app: AppRow) -> some View {
        let isOn = Binding(get: { app.itemIDs.contains(where: isHidden) },
                           set: { hide in for id in app.itemIDs { model.setHidden(id, hidden: hide) } })
        let caption = app.titles.isEmpty ? "Not running" : app.titles.joined(separator: " · ")
        return Toggle(isOn: isOn) {
            rowLabel(title: app.name, caption: caption, running: app.running)
        }
        .toggleStyle(.switch).tint(model.accent).padding(.vertical, 9)
        .accessibilityLabel("Hide every \(app.name) icon")
        .accessibilityHint(app.titles.isEmpty ? "Not running" : "Icons: \(app.titles.joined(separator: ", "))")
    }

    private func rowLabel(title: String, caption: String, running: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(running ? LokiStyle.text : LokiStyle.muted)
            Text(caption).font(.caption).foregroundStyle(LokiStyle.muted).lineLimit(2)
        }
        // Fill the row so the label sits leading and every switch lines up on the trailing edge.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowDivider: some View { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }

    private var words: [Substring] { filter.lowercased().split(separator: " ") }

    private var iconRows: [Candidate] {
        model.hidingCandidates.filter { row in words.allSatisfy { "\(row.title) \(row.owner)".lowercased().contains($0) } }
    }

    /// Groups every candidate by owning app, so a toggle covers all of an app's icons even
    /// when the filter matches only one. Items the allowlist cannot hide are left out.
    private var appRows: [AppRow] {
        let candidates = model.hidingCandidates.filter { MenuBarSections.hideable($0.id, allowlist: true) }
        let grouped = Dictionary(grouping: candidates) { MenuBarSections.owner(ofItem: $0.id) ?? $0.id }
        let apps = grouped.map { bundle, rows -> AppRow in
            let running = rows.filter(\.running)
            let titles = running.map(\.title).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            return AppRow(id: bundle, name: running.first?.owner ?? bundle, itemIDs: rows.map(\.id), titles: titles, running: !running.isEmpty)
        }
        return apps
            .filter { app in words.allSatisfy { "\(app.name) \(app.id) \(app.titles.joined(separator: " "))".lowercased().contains($0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func isHidden(_ id: String) -> Bool { model.realm.hiddenItems?.contains(id) ?? false }

    private var emptyText: String {
        if !filter.isEmpty { return visibility.usesAllowlist ? "No apps match." : "No icons match." }
        if model.menuExtras.isEmpty { return "Looking for menu-bar icons…" }
        return visibility.usesAllowlist ? "No third-party app icons to hide right now." : "No icons Loki can move right now."
    }

    // MARK: Status

    private var statusText: String {
        switch visibility.mode {
        case .arranging: return "Moving icons…"
        case .revealed: return "Showing hidden icons"
        case .idle: return "Nothing hidden"
        case .collapsed:
            if visibility.usesAllowlist {
                let apps = Set(visibility.hidden.compactMap(MenuBarSections.owner(ofItem:))).count
                return "\(apps) app\(apps == 1 ? "" : "s") hidden"
            }
            return "\(visibility.hidden.count) hidden"
        }
    }

    private var statusSpoken: String {
        switch visibility.mode {
        case .arranging: return "Hiding status: moving icons, please wait"
        case .revealed: return "Hiding status: hidden icons are showing"
        case .idle: return "Hiding status: nothing hidden"
        case .collapsed:
            if visibility.usesAllowlist { return "Hiding status: \(statusText)" }
            let count = visibility.hidden.count
            return "Hiding status: \(count) icon\(count == 1 ? "" : "s") hidden"
        }
    }

    private var statusPill: some View {
        let color: Color = visibility.mode == .idle ? LokiStyle.muted : (visibility.arranging ? .orange : model.accent)
        return pill(statusText, color: color, busy: visibility.arranging)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(statusSpoken)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private func pill(_ text: String, color: Color, busy: Bool) -> some View {
        HStack(spacing: 6) {
            if busy { ProgressView().controlSize(.mini).frame(width: 10, height: 10) }
            else { Circle().fill(color).frame(width: 6, height: 6) }
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.25)))
    }

    // MARK: Copy

    private var intro: String {
        switch visibility.backend {
        case .divider: return "Check the icons you want out of sight. Loki tucks them behind a divider and keeps them one click away."
        case .allowlist: return "Choose the apps whose icons you want out of sight. Loki keeps them one click away."
        case .unavailable: return "Loki can’t hide menu-bar icons on this version of macOS."
        }
    }

    @ViewBuilder private var backendNote: some View {
        switch visibility.backend {
        case .divider:
            Text("Loki Command-drags each chosen icon behind a hidden divider; your pointer moves for a moment. Clock and Control Center stay put; macOS pins them.")
                .font(.caption).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
        case .allowlist:
            VStack(alignment: .leading, spacing: 8) {
                Text("On macOS 27, hiding works per app: checking an app hides every icon it shows. Apple’s system controls aren’t listed because macOS 27 can’t hide them individually.")
                    .font(.caption).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
                Label("This uses an undocumented macOS interface. If a macOS update removes it, Loki switches hiding off and every icon stays visible.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
            }
        case .unavailable:
            EmptyView()
        }
    }

    private var gettingThere: String {
        if visibility.usesAllowlist {
            return "Option-click Loki’s rune, or right-click it and choose Show Hidden Icons. Option-click again to hide them."
        }
        return "Option-click Loki’s rune, or right-click it and choose Show Hidden Icons. Click the ‹ chevron to hide them again. Every hidden icon is also on Loki’s shelf."
    }

    private var footer: String {
        switch visibility.backend {
        case .divider: return "Loki uses only public macOS interfaces here: a status item for the divider and Accessibility to move icons. Quitting Loki shows every icon again. Loki never captures your screen."
        case .allowlist: return "Hiding lasts only while Loki runs: quitting Loki, or a crash, shows every icon again. Loki never captures your screen."
        case .unavailable: return "Loki never captures your screen, and it leaves your menu bar exactly as macOS arranges it."
        }
    }

    // MARK: Helpers

    private var listLocked: Bool { model.policy.hiddenItems != nil || model.policy.disableHiding }
    private var autoRehideOn: Bool { model.effectivePreferences.autoRehide ?? true }
    private var delay: Double { model.effectivePreferences.rehideDelay ?? 3 }
    /// Managed delays may reach 30 seconds; widen the slider only when one does.
    private var delayRange: ClosedRange<Double> { delay > 15 ? 1...30 : 1...15 }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(LokiStyle.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.04)))
    }

    private func textButton(_ title: String, symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.system(size: 12)) }
            .buttonStyle(.plain).foregroundStyle(model.accent).disabled(!enabled).opacity(enabled ? 1 : 0.4)
    }

    private func setting(_ key: WritableKeyPath<Preferences, Bool?>, default value: Bool) -> Binding<Bool> {
        Binding(get: { model.effectivePreferences[keyPath: key] ?? value },
                set: { model.preferences[keyPath: key] = $0; model.save(); model.applyHidingSettings() })
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
    let policy: ManagedPolicy
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("UPDATES").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(LokiStyle.muted)
            if policy.disableUpdates {
                ManagedCaption("Updates are managed by your organization")
            } else {
                controls
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(LokiStyle.surface, in: RoundedRectangle(cornerRadius: 14))
    }
    @ViewBuilder private var controls: some View {
        Toggle("Check for updates automatically", isOn: Binding(get: { updater.automaticChecks }, set: updater.setAutomaticChecks))
            .toggleStyle(.switch).tint(accent).disabled(policy.automaticUpdateChecks != nil)
        if policy.automaticUpdateChecks != nil { ManagedCaption() }
        Text("Updates are downloaded and verified before installation. Loki will ask before installing and relaunching. Checks contact the public update feed on GitHub; no shelf or group data is sent.")
            .font(.system(size: 12)).foregroundStyle(LokiStyle.muted).fixedSize(horizontal: false, vertical: true)
        Button("Check for updates…") { updater.checkForUpdates() }
            .buttonStyle(AccentButton(color: accent)).disabled(!updater.canCheck)
    }
}

/// Marks a control an organization's configuration profile has locked.
struct ManagedCaption: View {
    var text = "Managed by your organization"
    init(_ text: String? = nil) { if let text { self.text = text } }
    var body: some View {
        Label(text, systemImage: "building.2").font(.caption).foregroundStyle(LokiStyle.muted)
    }
}
