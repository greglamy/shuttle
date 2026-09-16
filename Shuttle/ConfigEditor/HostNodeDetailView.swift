//
//  HostNodeDetailView.swift
//  Shuttle
//
//  The form for the selected host entry: a command or a group.
//

import SwiftUI

struct HostNodeDetailView: View {
    let store: ShuttleConfigStore
    let nodeID: UUID

    var body: some View {
        Form {
            MenuTitleSection(name: nameBinding)

            if let command = store.node(id: nodeID)?.command {
                commandSections(command)
            } else if let children = store.node(id: nodeID)?.children {
                groupSection(children)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(store.node(id: nodeID)?.name.text ?? "")
    }

    // MARK: Command

    @ViewBuilder
    private func commandSections(_ command: HostCommand) -> some View {
        Section {
            TextField("Command", text: commandBinding.cmd, prompt: Text("ssh user@example.com"), axis: .vertical)
                .lineLimit(1...6)
                .font(.system(.body, design: .monospaced))
        } header: {
            Text("Command")
        } footer: {
            Text("Run in the terminal when the menu item is picked.")
        }

        Section {
            Picker("Opens in", selection: commandBinding.inTerminal) {
                Text("Use the global setting (\(store.configuration.settings.openIn.displayName))")
                    .tag(TerminalWindowMode?.none)
                Divider()
                ForEach(TerminalWindowMode.allCases) { mode in
                    Text(mode.displayName).tag(TerminalWindowMode?.some(mode))
                }
            }

            TextField(
                "Theme",
                text: commandBinding.theme,
                prompt: Text(globalThemePrompt)
            )

            TextField(
                "Window title",
                text: commandBinding.title,
                prompt: Text(titlePrompt)
            )
        } header: {
            Text("Terminal")
        } footer: {
            Text("Leave a field empty to inherit the global setting.")
        }

        if !command.extras.isEmpty {
            Section {
                ForEach(command.extras.keys.sorted(), id: \.self) { key in
                    LabeledContent(key) {
                        Text(String(describing: command.extras[key]?.anyValue ?? ""))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Other Keys")
            } footer: {
                Text("Shuttle does not use these, and this editor leaves them untouched when saving.")
            }
        }
    }

    private var globalThemePrompt: String {
        let theme = store.configuration.settings.defaultTheme
        if !theme.isEmpty { return theme }
        return store.configuration.settings.terminal == .iTerm ? "Default" : "basic"
    }

    private var titlePrompt: String {
        let name = store.node(id: nodeID)?.name.text ?? ""
        return name.isEmpty ? String(localized: "Menu title") : name
    }

    // MARK: Group

    @ViewBuilder
    private func groupSection(_ children: [HostNode]) -> some View {
        Section {
            LabeledContent("Entries") {
                Text(children.isEmpty ? String(localized: "Empty") : String(children.count))
                    .foregroundStyle(.secondary)
            }

            Button("New Command Inside", systemImage: "terminal") {
                store.add(.newCommand(), toGroup: nodeID)
            }

            Button("New Group Inside", systemImage: "folder") {
                store.add(.newGroup(), toGroup: nodeID)
            }
        } header: {
            Text("Submenu")
        } footer: {
            Text("A group becomes a submenu of the Shuttle menu.")
        }
    }

    // MARK: Bindings

    private var nameBinding: Binding<MenuItemName> {
        Binding(
            get: { store.node(id: nodeID)?.name ?? MenuItemName() },
            set: { newValue in store.update(id: nodeID) { $0.name = newValue } }
        )
    }

    private var commandBinding: Binding<HostCommand> {
        Binding(
            get: { store.node(id: nodeID)?.command ?? HostCommand() },
            set: { newValue in
                store.update(id: nodeID) { node in
                    if case .command = node.kind {
                        node.kind = .command(newValue)
                    }
                }
            }
        )
    }
}

// MARK: - Menu title

/// Title, forced sort position and trailing separator. Shuttle encodes the last
/// two inside the title string; this keeps the user out of that syntax.
private struct MenuTitleSection: View {
    @Binding var name: MenuItemName

    @FocusState private var sortKeyFocused: Bool

    var body: some View {
        Section {
            TextField("Name", text: $name.text, prompt: Text("Shown in the menu"))

            Toggle("Add a separator after this entry", isOn: $name.addsSeparator)

            Toggle("Force a position in the menu", isOn: sortOverrideBinding)

            if name.sortKey != nil {
                TextField("Sort key", text: sortKeyBinding, prompt: Text("aaa"))
                    .focused($sortKeyFocused)
                    .frame(maxWidth: 140)

                if let sortKey = name.sortKey, !MenuItemName.isValidSortKey(sortKey) {
                    Label("A sort key must be exactly three lowercase letters.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }
        } header: {
            Text("Menu Entry")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Shuttle sorts every menu alphabetically. The sort key is a hidden prefix that decides where this entry lands: \"aaa\" puts it first, \"zzz\" last.")
                if name.raw != name.text {
                    Text("Stored in the file as \(name.raw)")
                        .font(.caption)
                        .monospaced()
                }
            }
        }
    }

    private var sortOverrideBinding: Binding<Bool> {
        Binding(
            get: { name.sortKey != nil },
            set: { isOn in
                name.sortKey = isOn ? "aaa" : nil
                if isOn { sortKeyFocused = true }
            }
        )
    }

    private var sortKeyBinding: Binding<String> {
        Binding(
            get: { name.sortKey ?? "" },
            set: { newValue in
                // Keep only what Shuttle's own pattern accepts.
                let filtered = newValue.lowercased().filter { $0.isLetter && $0.isASCII }
                name.sortKey = String(filtered.prefix(MenuItemName.sortKeyLength))
            }
        )
    }
}
