//
//  ConfigEditorView.swift
//  Shuttle
//
//  The editor window: a source list of settings pages and the hosts tree on the
//  left, the form for whatever is selected on the right.
//

import SwiftUI

enum EditorSelection: Hashable {
    case general
    case terminal
    case sshConfig
    case node(UUID)
}

struct ConfigEditorView: View {
    let store: ShuttleConfigStore

    @State private var selection: EditorSelection? = .general
    @State private var showingWarnings = false
    @State private var saveFailure: String?
    @State private var showingOutsideChangeAlert = false
    /// The submenus that are closed in the sidebar. Tracking the closed ones
    /// rather than the open ones keeps every submenu visible by default, new
    /// ones included, so a drag has somewhere to land without extra clicks.
    @State private var collapsedGroups: Set<UUID> = []

    /// Declared explicitly: `@State` is a macro in the 27 SDK and memberwise
    /// init synthesis is not guaranteed for views that use it.
    init(store: ShuttleConfigStore) {
        self.store = store
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("Shuttle Configuration")
        .navigationSubtitle(store.fileURL.path(percentEncoded: false))
        .toolbar { toolbarContent }
        .frame(minWidth: 720, minHeight: 440)
        .alert("Could Not Save the Configuration", item: $saveFailure) { _ in
            Button("OK") {}
        } message: { failure in
            Text(failure)
        }
        .alert("The File Changed Outside Shuttle", isPresented: $showingOutsideChangeAlert) {
            Button("Overwrite", role: .destructive) { write() }
            Button("Reload from Disk") { store.load() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Another app or editor modified \(store.fileURL.lastPathComponent) after this window was opened. Overwriting discards those changes.")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Settings") {
                Label {
                    Text("General")
                } icon: {
                    EditorIcon(symbol: "gearshape", tint: .gray)
                }
                .tag(EditorSelection.general)

                Label {
                    Text("Terminal")
                } icon: {
                    EditorIcon(symbol: "apple.terminal", tint: .indigo)
                }
                .tag(EditorSelection.terminal)

                Label {
                    Text("SSH Config")
                } icon: {
                    EditorIcon(symbol: "key", tint: .orange)
                }
                .tag(EditorSelection.sshConfig)
            }

            Section("Hosts") {
                if store.configuration.hosts.isEmpty {
                    Text("No entry yet. Add a command or a group with the buttons below.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }

                ForEach(visibleRows) { row in
                    HostRowView(
                        node: row.node,
                        depth: row.depth,
                        isExpanded: !collapsedGroups.contains(row.id),
                        isSelected: selection == .node(row.id),
                        toggle: { toggleGroup(row.id) }
                    )
                    // The menu is built from the row under the pointer, so it
                    // acts on that entry and never on the submenu it sits in.
                    .contextMenu {
                        HostRowMenu(store: store, node: row.node, expand: expand)
                    }
                    // A reorderable row is a drag source, and the drag gesture
                    // takes the click before the list can turn it into a
                    // selection, so picking an entry is wired by hand. The
                    // gesture is simultaneous rather than exclusive: a tap only
                    // fires when the pointer did not move, so it never competes
                    // with an actual drag.
                    .simultaneousGesture(
                        TapGesture().onEnded { selection = .node(row.id) }
                    )
                    .tag(EditorSelection.node(row.id))
                }
                .reorderable()
            }
        }
        // The menu follows the order of the entries, so dragging a row is how
        // the position of an entry in the Shuttle menu is set.
        .reorderContainer(for: HostOutlineRow.self) { difference in
            switch difference.destination.position {
            case .end:
                store.reorderToEnd(ids: difference.sources)
            case .before(let targetID):
                store.reorder(ids: difference.sources, before: targetID)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        .onDeleteCommand { deleteSelection() }
        .background { moveShortcuts }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarActions
        }
    }

    /// Key equivalents for moving the selected entry, which the rows cannot
    /// carry themselves: the same commands sit in the contextual menu, and
    /// invisible buttons are how a plain view registers a shortcut.
    private var moveShortcuts: some View {
        HStack(spacing: 0) {
            Button("Move Up") { move(by: -1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])

            Button("Move Down") { move(by: 1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private var sidebarActions: some View {
        HStack(spacing: 2) {
            Menu {
                Button("New Command", systemImage: "terminal") { add(.newCommand()) }
                Button("New Group", systemImage: "folder") { add(.newGroup()) }
            } label: {
                Label("Add", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .menuIndicator(.hidden)
            .help("Add a command or a group")

            Button("Remove", systemImage: "minus") {
                deleteSelection()
            }
            .labelStyle(.iconOnly)
            .disabled(selectedNodeID == nil)
            .help("Remove the selected entry")

            Spacer()

            Menu {
                Button("Sort the Top Level by Name", systemImage: "arrow.up.arrow.down") {
                    store.sort(group: nil)
                }
                Button("Sort Every Menu by Name", systemImage: "arrow.up.arrow.down") {
                    store.sort(group: nil, recursively: true)
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
                    .labelStyle(.iconOnly)
            }
            .menuIndicator(.hidden)
            .help("Sort entries by name")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(alignment: .top) {
            VStack(spacing: 0) {
                Divider()
                Rectangle().fill(.bar)
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let loadFailure = store.loadFailure {
            ContentUnavailableView {
                Label("Could Not Read the Configuration", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadFailure)
            } actions: {
                Button("Try Again") { store.load() }
            }
        } else {
            switch selection {
            case .general:
                GeneralSettingsView(store: store)
            case .terminal:
                TerminalSettingsView(store: store)
            case .sshConfig:
                SSHConfigSettingsView(store: store)
            case .node(let id):
                if store.node(id: id) != nil {
                    HostNodeDetailView(store: store, nodeID: id)
                } else {
                    placeholder
                }
            case nil:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        ContentUnavailableView(
            "No Selection",
            systemImage: "sidebar.left",
            description: Text("Pick a settings page or a host in the sidebar.")
        )
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            if !store.warnings.isEmpty {
                Button {
                    showingWarnings = true
                } label: {
                    // Just the count: a pluralized noun would need a .stringsdict.
                    Label("\(store.warnings.count)", systemImage: "exclamationmark.triangle")
                }
                .help("Show configuration warnings")
                .popover(isPresented: $showingWarnings, arrowEdge: .bottom) {
                    WarningsList(warnings: store.warnings) { nodeID in
                        showingWarnings = false
                        if let nodeID { selection = .node(nodeID) }
                    }
                }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button("Revert") { store.revert() }
                .disabled(!store.isDirty)

            Button("Save") { save() }
                .keyboardShortcut("s")
                .buttonStyle(.glassProminent)
                .disabled(!store.isDirty || store.loadFailure != nil)
        }
    }

    // MARK: Rows

    /// The hosts tree flattened to the rows the sidebar shows. Flat rows keep
    /// every entry a list row of its own, which is what lets a drag reorder
    /// them and a right-click target the entry under the pointer.
    private var visibleRows: [HostOutlineRow] {
        HostOutlineRow.rows(for: store.configuration.hosts, collapsed: collapsedGroups)
    }

    private func toggleGroup(_ id: UUID) {
        withAnimation {
            if collapsedGroups.contains(id) {
                collapsedGroups.remove(id)
            } else {
                collapsedGroups.insert(id)
            }
        }
    }

    private func expand(_ id: UUID) {
        collapsedGroups.remove(id)
    }

    // MARK: Actions

    private var selectedNodeID: UUID? {
        if case .node(let id) = selection { id } else { nil }
    }

    private func add(_ node: HostNode) {
        let parent = store.insertionTarget(for: selectedNodeID)
        if let parent { expand(parent) }
        selection = .node(store.add(node, toGroup: parent))
    }

    private func deleteSelection() {
        guard let id = selectedNodeID else { return }
        selection = nil
        store.remove(id: id)
    }

    private func move(by offset: Int) {
        guard let id = selectedNodeID else { return }
        withAnimation(.snappy(duration: 0.18)) {
            store.move(id: id, by: offset)
        }
    }

    private func save() {
        if store.fileChangedOutsideEditor {
            showingOutsideChangeAlert = true
        } else {
            write()
        }
    }

    private func write() {
        do {
            try store.save()
        } catch {
            saveFailure = error.localizedDescription
        }
    }
}

// MARK: - Hosts outline

/// One row of the flattened hosts outline.
private struct HostOutlineRow: Identifiable {
    let node: HostNode
    /// How deep the entry sits in the tree, used to indent the row.
    let depth: Int

    var id: UUID { node.id }

    static func rows(for nodes: [HostNode], collapsed: Set<UUID>, depth: Int = 0) -> [HostOutlineRow] {
        nodes.flatMap { node in
            let row = HostOutlineRow(node: node, depth: depth)
            guard let children = node.children, !collapsed.contains(node.id) else { return [row] }
            return [row] + rows(for: children, collapsed: collapsed, depth: depth + 1)
        }
    }
}

private struct HostRowView: View {
    let node: HostNode
    let depth: Int
    let isExpanded: Bool
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            if node.isGroup {
                Button(action: toggle) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 14, height: 14)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? Text("Collapse") : Text("Expand"))
            } else {
                Color.clear
                    .frame(width: 14, height: 14)
            }

            Label {
                Text(node.name.text.isEmpty ? String(localized: "Untitled") : node.name.text)
                    .italic(node.name.text.isEmpty)
            } icon: {
                EditorIcon(
                    symbol: node.isGroup ? "folder.fill" : "apple.terminal.fill",
                    tint: node.isGroup ? .shuttleGroup : .shuttleCommand
                )
            }
        }
        .padding(.leading, CGFloat(depth) * 14)
        // Make the whole width of the row selectable and right-clickable, not
        // just the text.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        // Drawn here rather than left to the list: a reorderable row does not
        // carry its `tag` to the list, so the list never knows it is the
        // selected one and would show nothing.
        .background(
            isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
            in: .rect(cornerRadius: 6)
        )
        .contentShape(.rect)
    }
}

private struct HostRowMenu: View {
    let store: ShuttleConfigStore
    let node: HostNode
    /// Opens a submenu, so an entry added inside a closed one stays visible.
    let expand: (UUID) -> Void

    var body: some View {
        if node.isGroup {
            Button("New Command Inside", systemImage: "terminal") {
                expand(node.id)
                store.add(.newCommand(), toGroup: node.id)
            }
            Button("New Group Inside", systemImage: "folder") {
                expand(node.id)
                store.add(.newGroup(), toGroup: node.id)
            }
            Divider()
        }

        Button("Duplicate", systemImage: "plus.square.on.square") {
            store.duplicate(id: node.id)
        }

        Divider()

        Button("Move Up", systemImage: "arrow.up") {
            store.move(id: node.id, by: -1)
        }
        .keyboardShortcut(.upArrow, modifiers: [.command, .option])
        .disabled(!store.canMove(id: node.id, by: -1))

        Button("Move Down", systemImage: "arrow.down") {
            store.move(id: node.id, by: 1)
        }
        .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        .disabled(!store.canMove(id: node.id, by: 1))

        if node.isGroup, let children = node.children, children.count > 1 {
            Button("Sort Contents by Name", systemImage: "arrow.up.arrow.down") {
                store.sort(group: node.id)
            }
        }

        let destinations = store.moveDestinations(for: node.id)
        if !destinations.isEmpty {
            Menu("Move to") {
                ForEach(destinations, id: \.path) { destination in
                    Button(destination.path) {
                        if let id = destination.id { expand(id) }
                        store.move(id: node.id, toGroup: destination.id)
                    }
                }
            }
        }

        Divider()

        Button("Delete", systemImage: "trash", role: .destructive) {
            store.remove(id: node.id)
        }
    }
}

// MARK: - Warnings

private struct WarningsList: View {
    let warnings: [ShuttleConfigStore.Warning]
    let onSelect: (UUID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Warnings")
                .font(.headline)

            Text("Shuttle ignores these silently when it builds the menu.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(warnings) { warning in
                        Button {
                            onSelect(warning.nodeID)
                        } label: {
                            Label(warning.message, systemImage: "exclamationmark.triangle")
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .disabled(warning.nodeID == nil)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(14)
        .frame(width: 360)
    }
}

// MARK: - Preview

#if DEBUG
/// The store is held in `@State` on purpose: rebuilding it on every render
/// would hand the list a tree of brand new node identities each time, which
/// leaves the rows blank and can trip an assertion inside `List`.
private struct EditorPreview: View {
    @State private var store = ShuttleConfigStore(
        fileURL: Bundle.main.url(forResource: "shuttle.default", withExtension: "json")
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".shuttle.json")
    )

    var body: some View {
        ConfigEditorView(store: store)
    }
}

/// Shows the settings pages and the window chrome. The host rows stay blank
/// here: the reorderable list needs the real window to lay its rows out, and
/// previewing it either renders nothing or trips an assertion inside `List`.
/// Use the "Sidebar rows" preview below to work on a row.
#Preview("Editor") {
    EditorPreview()
}
#endif

#if DEBUG
#Preview("Sidebar rows") {
    List {
        Section("Hosts") {
            HostRowView(node: .newGroup(), depth: 0, isExpanded: true, isSelected: false, toggle: {})
            HostRowView(node: .newCommand(), depth: 1, isExpanded: false, isSelected: true, toggle: {})
            HostRowView(node: .newCommand(), depth: 1, isExpanded: false, isSelected: false, toggle: {})
            HostRowView(node: .newGroup(), depth: 0, isExpanded: false, isSelected: true, toggle: {})
        }
    }
    .listStyle(.sidebar)
    .frame(width: 250, height: 200)
}
#endif
