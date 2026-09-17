//
//  ShuttleMenuPanel.swift
//  Shuttle
//
//  The status item panel: a searchable, browsable presentation of the menu
//  AppDelegate already builds.
//
//  It deliberately renders the live `NSMenu` rather than re-reading the
//  configuration: every entry keeps its own target/action, so picking a row runs
//  exactly the same code the classic menu ran, with the same handling of themes,
//  window modes and hosts merged in from ~/.ssh/config. Right-clicking the
//  status item still shows that classic menu.
//

import AppKit
import SwiftUI

@objc(ShuttleMenuPanel)
public final class ShuttleMenuPanel: NSObject {
    private static let controller = MenuPanelController()

    /// Shows the panel under the status item, or closes it when already open.
    ///
    /// `appItemCount` is the number of trailing items of `menu` that are
    /// Shuttle's own commands (Settings, About, Quit) rather than hosts.
    @objc(togglePanelFromButton:menu:appItemCount:)
    public static func toggle(from button: NSStatusBarButton, menu: NSMenu, appItemCount: Int) {
        controller.toggle(from: button, menu: menu, appItemCount: appItemCount)
    }

    @objc(closePanel)
    public static func close() {
        controller.close()
    }
}

// MARK: - Presentation

@MainActor
private final class MenuPanelController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private weak var button: NSStatusBarButton?
    /// When the panel last closed. A transient popover dismisses itself on the
    /// click that lands on the status item, and the button's action then runs,
    /// so without this the panel would immediately reopen and never toggle off.
    private var closedAt: Date?

    override init() {
        super.init()
        popover.behavior = .transient
        popover.delegate = self
    }

    func toggle(from button: NSStatusBarButton, menu: NSMenu, appItemCount: Int) {
        if popover.isShown {
            close()
            return
        }

        if let closedAt, Date.now.timeIntervalSince(closedAt) < 0.3 {
            return
        }

        let model = MenuPanelModel(menu: menu, appItemCount: appItemCount)
        model.run = { [weak self] item in self?.run(item) }
        model.dismiss = { [weak self] in self?.close() }

        popover.contentViewController = NSHostingController(rootView: MenuPanelView(model: model))
        self.button = button

        // The app is an LSUIElement, so it has to be activated for the search
        // field in the panel to receive what the person types.
        NSApp.activate()
        button.highlight(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func close() {
        popover.performClose(nil)
    }

    private func run(_ item: NSMenuItem) {
        close()
        guard let action = item.action else { return }
        // Let the panel finish closing before the terminal comes up.
        Task { @MainActor in
            NSApp.sendAction(action, to: item.target, from: item)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        button?.highlight(false)
        closedAt = .now

        // Drop the hosting controller, so the next opening is built from a fresh
        // menu. Deferred: the popover is still tearing its window down here.
        Task { @MainActor in
            if !popover.isShown {
                popover.contentViewController = nil
            }
        }
    }
}

// MARK: - Model

/// The menu, flattened into something a SwiftUI list can show.
@MainActor
@Observable
final class MenuPanelModel {
    struct Entry: Identifiable {
        enum Kind {
            case command(NSMenuItem)
            case group([Entry])
            case separator
        }

        let id = UUID()
        let title: String
        let kind: Kind
        /// Titles of the submenus above this entry, used as a subtitle in search
        /// results and as the stable key of a favourite.
        let parents: [String]

        /// The command line of a host entry, shown under its name.
        let detail: String?

        var isGroup: Bool {
            if case .group = kind { true } else { false }
        }

        var children: [Entry]? {
            if case .group(let children) = kind { children } else { nil }
        }

        var menuItem: NSMenuItem? {
            if case .command(let item) = kind { item } else { nil }
        }

        var key: String { (parents + [title]).joined(separator: " ▸ ") }
    }

    /// The host entries: everything the configuration and ~/.ssh/config produced.
    let hosts: [Entry]
    /// Shuttle's own commands, shown in the gear menu.
    let appCommands: [Entry]

    var favourites = MenuPanelFavourites()

    var run: ((NSMenuItem) -> Void)?
    var dismiss: (() -> Void)?

    init(menu: NSMenu, appItemCount: Int) {
        let items = menu.items
        let hostCount = max(0, items.count - appItemCount)

        hosts = Self.entries(of: Array(items.prefix(hostCount)), parents: [])
        appCommands = Self.entries(of: Array(items.suffix(from: hostCount)), parents: [])
    }

    private static func entries(of items: [NSMenuItem], parents: [String]) -> [Entry] {
        items.map { item in
            if item.isSeparatorItem {
                return Entry(title: "", kind: .separator, parents: parents, detail: nil)
            }
            if let submenu = item.submenu {
                return Entry(
                    title: item.title,
                    kind: .group(entries(of: submenu.items, parents: parents + [item.title])),
                    parents: parents,
                    detail: nil
                )
            }
            return Entry(
                title: item.title,
                kind: .command(item),
                parents: parents,
                detail: commandLine(of: item)
            )
        }
    }

    /// The command AppDelegate packed into the represented object, for display
    /// only. The separator is the one `openHost:` splits on.
    private static func commandLine(of item: NSMenuItem) -> String? {
        guard let packed = item.representedObject as? String else { return nil }
        let command = packed.components(separatedBy: "¬_¬").first ?? ""
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "(null)" ? nil : trimmed
    }

    // MARK: Search

    /// Every host command in the tree, deepest paths included.
    private var allCommands: [Entry] {
        func flatten(_ entries: [Entry]) -> [Entry] {
            entries.flatMap { entry -> [Entry] in
                switch entry.kind {
                case .command: return [entry]
                case .group(let children): return flatten(children)
                case .separator: return []
                }
            }
        }
        return flatten(hosts)
    }

    /// Commands matching every whitespace-separated word of `query`, in their
        /// name, their command line or the submenus they sit in.
    func results(for query: String) -> [Entry] {
        let words = query.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }

        return allCommands.filter { entry in
            let haystack = ([entry.title, entry.detail ?? ""] + entry.parents).joined(separator: " ")
            return words.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
        }
    }

    /// The starred commands that still exist in the menu, in the order they were
    /// starred.
    ///
    /// Only commands that live in a submenu: the point of a favourite is to lift
    /// a buried host to the top, and a top-level one would just be listed twice.
    var favouriteEntries: [Entry] {
        let commands = allCommands
        return favourites.keys.compactMap { key in
            commands.first { $0.key == key && !$0.parents.isEmpty }
        }
    }
}

/// The starred commands, kept in user defaults and keyed by their menu path so
/// they survive a rebuild of the menu.
@MainActor
@Observable
final class MenuPanelFavourites {
    private static let defaultsKey = "ShuttleMenuFavourites"

    var keys: [String] {
        didSet { UserDefaults.standard.set(keys, forKey: Self.defaultsKey) }
    }

    init() {
        keys = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
    }

    func contains(_ key: String) -> Bool { keys.contains(key) }

    func toggle(_ key: String) {
        if let index = keys.firstIndex(of: key) {
            keys.remove(at: index)
        } else {
            keys.append(key)
        }
    }
}

// MARK: - Panel

private struct MenuPanelView: View {
    let model: MenuPanelModel

    /// The submenus that have been opened, deepest last.
    @State private var breadcrumb: [MenuPanelModel.Entry] = []
    @State private var query = ""
    @State private var keyboardSelection = 0
    @State private var hovered: UUID?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            Divider()
                .padding(.top, 10)
            rows
        }
        .frame(width: 330)
        .onChange(of: query) { keyboardSelection = 0 }
        .onChange(of: breadcrumb.count) { keyboardSelection = 0 }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            if breadcrumb.isEmpty {
                // The menu bar glyph, so the panel reads as the same object the
                // person just clicked.
                Image(nsImage: NSImage(named: "StatusIcon") ?? NSApp.applicationIconImage)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 15, height: 15)
                    .foregroundStyle(.primary)

                Text(verbatim: "Shuttle")
                    .font(.headline)
            } else {
                Button {
                    withAnimation(.snappy(duration: 0.18)) { breadcrumb.removeLast() }
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Back")

                Text(breadcrumb.last?.title ?? "")
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Menu {
                AppCommandMenuItems(entries: model.appCommands, model: model)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Shuttle settings")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search hosts", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { activate(visibleEntries.indices.contains(keyboardSelection) ? visibleEntries[keyboardSelection] : nil) }
                .onKeyPress(.downArrow) { moveSelection(by: 1) }
                .onKeyPress(.upArrow) { moveSelection(by: -1) }
                .onKeyPress(.leftArrow) {
                    // Only when the field is empty, so it stays a text cursor
                    // key while something is typed.
                    guard query.isEmpty, !breadcrumb.isEmpty else { return .ignored }
                    withAnimation(.snappy(duration: 0.18)) { breadcrumb.removeLast() }
                    return .handled
                }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.quinary, in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(searchFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: 1)
        }
        .padding(.horizontal, 14)
        .task { searchFocused = true }
    }

    // MARK: Rows

    @ViewBuilder
    private var rows: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if isSearching {
                    if visibleEntries.isEmpty {
                        emptyState(
                            title: String(localized: "No Match"),
                            message: String(localized: "No host matches what you typed."),
                            symbol: "magnifyingglass"
                        )
                    } else {
                        sectionLabel("Results")
                        entryRows(visibleEntries, showsPath: true)
                    }
                } else {
                    if breadcrumb.isEmpty, !model.favouriteEntries.isEmpty {
                        sectionLabel("Favorites")
                        entryRows(model.favouriteEntries, showsPath: true)
                        Divider().padding(.vertical, 6)
                    }

                    if currentEntries.isEmpty {
                        emptyState(
                            title: String(localized: "Nothing Here"),
                            message: String(localized: "This submenu has no entry."),
                            symbol: "folder"
                        )
                    } else {
                        entryRows(visibleEntries, showsPath: false, separators: currentEntries)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 360)
        .scrollBounceBehavior(.basedOnSize)
    }

    /// The rows, with the separators of the original menu kept as dividers when
    /// the whole submenu is shown.
    @ViewBuilder
    private func entryRows(
        _ entries: [MenuPanelModel.Entry],
        showsPath: Bool,
        separators: [MenuPanelModel.Entry]? = nil
    ) -> some View {
        let listed = separators ?? entries

        ForEach(Array(listed.enumerated()), id: \.element.id) { _, entry in
            switch entry.kind {
            case .separator:
                Divider()
                    .padding(.vertical, 5)
                    .padding(.horizontal, 6)

            case .command, .group:
                let index = entries.firstIndex { $0.id == entry.id }

                MenuPanelRow(
                    entry: entry,
                    showsPath: showsPath,
                    isSelected: hovered == entry.id || (hovered == nil && index == keyboardSelection),
                    isFavourite: model.favourites.contains(entry.key),
                    toggleFavourite: { model.favourites.toggle(entry.key) },
                    activate: { activate(entry) }
                )
                .onHover { inside in
                    hovered = inside ? entry.id : (hovered == entry.id ? nil : hovered)
                    if inside, let index { keyboardSelection = index }
                }
            }
        }
    }

    private func sectionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.top, 2)
            .padding(.bottom, 4)
    }

    private func emptyState(title: String, message: String, symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.callout.weight(.medium))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    // MARK: State

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The entries of the submenu being browsed, separators included.
    private var currentEntries: [MenuPanelModel.Entry] {
        breadcrumb.last?.children ?? model.hosts
    }

    /// The pickable entries, in the order the arrow keys walk them.
    private var visibleEntries: [MenuPanelModel.Entry] {
        if isSearching { return model.results(for: query) }
        let listed = currentEntries.filter { if case .separator = $0.kind { false } else { true } }
        guard breadcrumb.isEmpty else { return listed }
        return model.favouriteEntries + listed
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        let entries = visibleEntries
        guard !entries.isEmpty else { return .ignored }
        hovered = nil
        keyboardSelection = (keyboardSelection + offset + entries.count) % entries.count
        return .handled
    }

    private func activate(_ entry: MenuPanelModel.Entry?) {
        guard let entry else { return }

        switch entry.kind {
        case .group:
            query = ""
            withAnimation(.snappy(duration: 0.18)) { breadcrumb.append(entry) }
        case .command(let item):
            model.run?(item)
        case .separator:
            break
        }
    }
}

// MARK: - Row

private struct MenuPanelRow: View {
    let entry: MenuPanelModel.Entry
    /// Shows the submenus the entry lives in, for favourites and results.
    let showsPath: Bool
    let isSelected: Bool
    let isFavourite: Bool
    let toggleFavourite: () -> Void
    let activate: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: activate) {
            HStack(spacing: 9) {
                Image(systemName: entry.isGroup ? "folder.fill" : "apple.terminal.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(entry.isGroup ? Color.shuttleGroup : .shuttleCommand)
                    .frame(width: 22, height: 22)
                    .background(
                        (entry.isGroup ? Color.shuttleGroup : .shuttleCommand).opacity(0.16),
                        in: .rect(cornerRadius: 6)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title.isEmpty ? String(localized: "Untitled") : entry.title)
                        .font(.system(size: 13))
                        .lineLimit(1)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 4)

                if entry.isGroup {
                    Text(String(entry.children?.filter { if case .separator = $0.kind { false } else { true } }.count ?? 0))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Image(systemName: "chevron.forward")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else if canBeFavourite, isFavourite || isHovered || isSelected {
                    Button(action: toggleFavourite) {
                        Image(systemName: isFavourite ? "star.fill" : "star")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isFavourite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                    }
                    .buttonStyle(.plain)
                    .help(isFavourite ? "Remove from favorites" : "Add to favorites")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AnyShapeStyle(.tint.tertiary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 7))
            .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var subtitle: String? {
        if showsPath, !entry.parents.isEmpty {
            return entry.parents.joined(separator: " ▸ ")
        }
        return entry.detail
    }

    /// Only a command inside a submenu can be starred; see `favouriteEntries`.
    private var canBeFavourite: Bool {
        !entry.isGroup && !entry.parents.isEmpty
    }
}

// MARK: - Preview

#if DEBUG
/// A stand-in for the menu AppDelegate builds, so the panel can be laid out
/// without the app running.
private func previewMenu() -> NSMenu {
    func command(_ title: String, _ command: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.representedObject = "\(command)¬_¬(null)¬_¬(null)¬_¬(null)¬_¬\(title)"
        return item
    }

    func group(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let submenu = NSMenu()
        items.forEach { submenu.addItem($0) }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    let menu = NSMenu()
    menu.addItem(group("Production", [
        command("db-01", "ssh root@db-01.example.com"),
        command("web-01", "ssh root@web-01.example.com"),
        command("web-02", "ssh root@web-02.example.com"),
    ]))
    menu.addItem(group("Staging", [command("staging", "ssh deploy@staging.example.com")]))
    menu.addItem(.separator())
    menu.addItem(command("localhost", "ssh localhost"))
    menu.addItem(command("nas", "ssh greg@nas.local"))
    menu.addItem(.separator())
    menu.addItem(group("Settings", [NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")]))
    menu.addItem(NSMenuItem(title: "About", action: nil, keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Quit", action: nil, keyEquivalent: ""))
    return menu
}

#Preview("Menu panel") {
    MenuPanelView(model: MenuPanelModel(menu: previewMenu(), appItemCount: 4))
}
#endif

// MARK: - Gear menu

/// Shuttle's own menu items, rebuilt as SwiftUI menu entries so they keep their
/// submenus (Settings) and their actions.
private struct AppCommandMenuItems: View {
    let entries: [MenuPanelModel.Entry]
    let model: MenuPanelModel

    var body: some View {
        ForEach(entries) { entry in
            switch entry.kind {
            case .separator:
                Divider()

            case .group(let children):
                Menu(entry.title) {
                    AppCommandMenuItems(entries: children, model: model)
                }

            case .command(let item):
                Button(entry.title) { model.run?(item) }
                    .disabled(!item.isEnabled)
            }
        }
    }
}
