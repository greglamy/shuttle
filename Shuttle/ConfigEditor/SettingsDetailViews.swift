//
//  SettingsDetailViews.swift
//  Shuttle
//
//  The three global settings pages of the editor window.
//

import AppKit
import SwiftUI

// MARK: - General

struct GeneralSettingsView: View {
    @Bindable var store: ShuttleConfigStore

    var body: some View {
        Form {
            Section {
                Toggle("Launch Shuttle at login", isOn: $store.configuration.settings.launchAtLogin)
            } footer: {
                Text("Applied the next time Shuttle reloads its menu.")
            }

            Section {
                TextField("Text editor", text: $store.configuration.settings.editor, prompt: Text("default"))
            } header: {
                Text("Editing the File by Hand")
            } footer: {
                Text("\"default\" opens the configuration with the app macOS associates with JSON. Any other value is run as a terminal command, for example \"nano\" or \"vi\".")
            }

            Section {
                LabeledContent("Configuration file") {
                    HStack(spacing: 8) {
                        Text(store.fileURL.path(percentEncoded: false))
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Button("Show in Finder", systemImage: "folder") {
                            NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

// MARK: - Terminal

struct TerminalSettingsView: View {
    @Bindable var store: ShuttleConfigStore

    private var usesITerm: Bool { store.configuration.settings.terminal == .iTerm }

    var body: some View {
        Form {
            Section {
                Picker("Open commands with", selection: $store.configuration.settings.terminal) {
                    ForEach(TerminalApp.allCases) { app in
                        Text(app.displayName).tag(app)
                    }
                }

                Picker("iTerm version", selection: $store.configuration.settings.iTermVersion) {
                    ForEach(ITermVersion.allCases) { version in
                        Text(version.displayName).tag(version)
                    }
                }
                .disabled(!usesITerm)
            } footer: {
                if usesITerm {
                    Text("Stable and nightly iTerm builds need different AppleScript, so this has to match the build you run.")
                }
            }

            Section {
                Picker("By default, open in", selection: $store.configuration.settings.openIn) {
                    ForEach(TerminalWindowMode.globalDefaults) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                TextField(
                    "Default theme",
                    text: $store.configuration.settings.defaultTheme,
                    prompt: Text(usesITerm ? "Default" : "basic")
                )
            } header: {
                Text("Defaults for Every Command")
            } footer: {
                Text(usesITerm
                     ? "The name of an iTerm profile. Individual commands can override both settings."
                     : "The name of a Terminal.app profile. Individual commands can override both settings.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Terminal")
    }
}

// MARK: - SSH config

struct SSHConfigSettingsView: View {
    @Bindable var store: ShuttleConfigStore

    var body: some View {
        Form {
            Section {
                Toggle("Show hosts from ~/.ssh/config", isOn: $store.configuration.settings.showSSHConfigHosts)
            } footer: {
                Text("Hosts read from your SSH config are added to the menu alongside the ones defined here. Entries containing \"*\" or starting with \".\" are always skipped.")
            }

            if store.configuration.settings.showSSHConfigHosts {
                Section {
                    StringListEditor(
                        values: $store.configuration.settings.sshConfigIgnoreHosts,
                        prompt: "host name",
                        addTitle: "Add a Host"
                    )
                } header: {
                    Text("Ignored Hosts")
                } footer: {
                    Text("Skipped when the host name matches exactly.")
                }

                Section {
                    StringListEditor(
                        values: $store.configuration.settings.sshConfigIgnoreKeywords,
                        prompt: "keyword",
                        addTitle: "Add a Keyword"
                    )
                } header: {
                    Text("Ignored Keywords")
                } footer: {
                    Text("Skipped when the host name contains the keyword anywhere.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("SSH Config")
    }
}

// MARK: - Reusable list of strings

struct StringListEditor: View {
    @Binding var values: [String]
    let prompt: LocalizedStringKey
    let addTitle: LocalizedStringKey

    var body: some View {
        if values.isEmpty {
            Text("None")
                .foregroundStyle(.secondary)
        }

        ForEach(Array($values.enumerated()), id: \.offset) { offset, value in
            HStack(spacing: 6) {
                TextField(prompt, text: value, prompt: Text(prompt))
                    .labelsHidden()

                Button("Remove", systemImage: "minus.circle.fill") {
                    // The offset is captured at render time, so re-check it.
                    if offset < values.count {
                        values.remove(at: offset)
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }

        Button(addTitle, systemImage: "plus") {
            values.append("")
        }
    }
}
