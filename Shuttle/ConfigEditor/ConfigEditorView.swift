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
                Label("General", systemImage: "gearshape")
                    .tag(EditorSelection.general)
                Label("Terminal", systemImage: "apple.terminal")
                    .tag(EditorSelection.terminal)
                Label("SSH Config", systemImage: "key")
                    .tag(EditorSelection.sshConfig)
            }

            Section("Hosts") {
                HostOutlineRows(store: store, nodes: store.configuration.hosts)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        .onDeleteCommand { deleteSelection() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarActions
        }
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
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
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
                .disabled(!store.isDirty || store.loadFailure != nil)
        }
    }

    // MARK: Actions

    private var selectedNodeID: UUID? {
        if case .node(let id) = selection { id } else { nil }
    }

    private func add(_ node: HostNode) {
        let parent = store.insertionTarget(for: selectedNodeID)
        selection = .node(store.add(node, toGroup: parent))
    }

    private func deleteSelection() {
        guard let id = selectedNodeID else { return }
        selection = nil
        store.remove(id: id)
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

/// Recursive sidebar rows for the hosts tree. Written by hand rather than with
/// `OutlineGroup` so each row can carry an explicit `EditorSelection` tag.
private struct HostOutlineRows: View {
    let store: ShuttleConfigStore
    let nodes: [HostNode]

    var body: some View {
        ForEach(nodes) { node in
            if let children = node.children {
                DisclosureGroup {
                    HostOutlineRows(store: store, nodes: children)
                } label: {
                    HostRowLabel(node: node)
                }
                .tag(EditorSelection.node(node.id))
                .contextMenu { HostRowMenu(store: store, node: node) }
            } else {
                HostRowLabel(node: node)
                    .tag(EditorSelection.node(node.id))
                    .contextMenu { HostRowMenu(store: store, node: node) }
            }
        }
    }
}

private struct HostRowLabel: View {
    let node: HostNode

    var body: some View {
        Label {
            Text(node.name.text.isEmpty ? String(localized: "Untitled") : node.name.text)
                .italic(node.name.text.isEmpty)
        } icon: {
            Image(systemName: node.isGroup ? "folder" : "terminal")
        }
    }
}

private struct HostRowMenu: View {
    let store: ShuttleConfigStore
    let node: HostNode

    var body: some View {
        if node.isGroup {
            Button("New Command Inside", systemImage: "terminal") {
                store.add(.newCommand(), toGroup: node.id)
            }
            Button("New Group Inside", systemImage: "folder") {
                store.add(.newGroup(), toGroup: node.id)
            }
            Divider()
        }

        Button("Duplicate", systemImage: "plus.square.on.square") {
            store.duplicate(id: node.id)
        }

        let destinations = store.moveDestinations(for: node.id)
        if !destinations.isEmpty {
            Menu("Move to") {
                ForEach(destinations, id: \.path) { destination in
                    Button(destination.path) {
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
