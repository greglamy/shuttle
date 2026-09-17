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

/// Title and trailing separator. Shuttle encodes the separator inside the title
/// string; this keeps the user out of that syntax.
private struct MenuTitleSection: View {
    @Binding var name: MenuItemName

    var body: some View {
        Section {
            TextField("Name", text: $name.text, prompt: Text("Shown in the menu"))

            Toggle("Add a separator after this entry", isOn: $name.addsSeparator)
        } header: {
            Text("Menu Entry")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Entries appear in the menu in the order they have in the sidebar. Drag a row there to move it, or drop it just under an open group to file it in that submenu.")
                if name.raw != name.text {
                    Text("Stored in the file as \(name.raw)")
                        .font(.caption)
                        .monospaced()
                }
            }
        }
    }
}
