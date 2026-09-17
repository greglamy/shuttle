//
//  SettingsDetailViews.swift
//  Shuttle
//
//  The three global settings pages of the editor window.
//

import AppKit
import SwiftUI

// MARK: - Shared chrome

extension Color {
    /// The badge colour of a submenu.
    static let shuttleGroup = Color.accentColor

    /// The badge colour of a command. Mixed with black on purpose: at badge
    /// size, saturated teal plus the badge gradient washes the white glyph out.
    static let shuttleCommand = Color.teal.mix(with: .black, by: 0.4)
}

/// The symbol that stands for a section of the editor, in a tinted badge. Used
/// in the sidebar and at the top of each page so the two match.
struct EditorIcon: View {
    let symbol: String
    let tint: Color
    /// The side of the badge; the glyph scales with it.
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: symbol)
            // Drawn to a box rather than set in a point size: a symbol keeps its
            // own proportions, so a font size that looks right on a large badge
            // leaves only a pixel or two of margin on a small one and reads as
            // a clipped icon. This keeps the margin at a fixed share of the
            // badge whatever the size.
            .resizable()
            .aspectRatio(contentMode: .fit)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(width: size * 0.54, height: size * 0.54)
            .frame(width: size, height: size)
            .background(tint.gradient, in: .rect(cornerRadius: size * 0.3))
    }
}

/// The title block at the top of a detail page: what the page is, in one line.
struct EditorPageHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            EditorIcon(symbol: symbol, tint: tint, size: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 2)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @Bindable var store: ShuttleConfigStore

    var body: some View {
        VStack(spacing: 0) {
            EditorPageHeader(
                title: String(localized: "General"),
                subtitle: String(localized: "How Shuttle starts and where its configuration lives."),
                symbol: "gearshape",
                tint: .gray
            )

            form
        }
        .navigationTitle("General")
    }

    private var form: some View {
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
    }
}

// MARK: - Terminal

struct TerminalSettingsView: View {
    @Bindable var store: ShuttleConfigStore

    private var usesITerm: Bool { store.configuration.settings.terminal == .iTerm }

    var body: some View {
        VStack(spacing: 0) {
            EditorPageHeader(
                title: String(localized: "Terminal"),
                subtitle: String(localized: "Which terminal runs your commands, and how it opens them."),
                symbol: "apple.terminal",
                tint: .indigo
            )

            form
        }
        .navigationTitle("Terminal")
    }

    private var form: some View {
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
    }
}

// MARK: - SSH config

struct SSHConfigSettingsView: View {
    @Bindable var store: ShuttleConfigStore

    var body: some View {
        VStack(spacing: 0) {
            EditorPageHeader(
                title: String(localized: "SSH Config"),
                subtitle: String(localized: "Add the hosts of ~/.ssh/config to the menu, minus the ones you skip."),
                symbol: "key",
                tint: .orange
            )

            form
        }
        .navigationTitle("SSH Config")
    }

    private var form: some View {
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
