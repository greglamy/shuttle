//
//  ShuttleConfiguration.swift
//  Shuttle
//
//  A typed, editable representation of ~/.shuttle.json.
//
//  The file is round-tripped rather than rewritten from scratch: any key this
//  editor does not know about (including the "_comments" block) is preserved
//  verbatim so that hand-written configurations survive a save.
//

import Foundation

// MARK: - Loss-free JSON passthrough

/// A JSON value used to carry keys the editor does not model explicitly.
enum JSONValue: Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init?(_ any: Any) {
        switch any {
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            // Bools bridge to NSNumber, so the CoreFoundation type decides.
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case let value as [Any]:
            self = .array(value.compactMap(JSONValue.init))
        case let value as [String: Any]:
            self = .object(value.compactMapValues(JSONValue.init))
        case is NSNull:
            self = .null
        default:
            return nil
        }
    }

    var anyValue: Any {
        switch self {
        case .string(let value): value
        case .number(let value): value
        case .bool(let value): value
        case .null: NSNull()
        case .array(let value): value.map(\.anyValue)
        case .object(let value): value.mapValues(\.anyValue)
        }
    }
}

// MARK: - Enumerated settings

/// Mirrors the `terminal` key. `AppDelegate` lowercases the value and compares
/// it against "iterm", so the raw strings below must keep their exact spelling.
enum TerminalApp: String, CaseIterable, Identifiable, Hashable {
    case terminal = "Terminal.app"
    case iTerm = "iTerm"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .terminal: "Terminal.app"
        case .iTerm: "iTerm"
        }
    }
}

/// Mirrors the `iTerm_version` key, which selects the AppleScript variant used.
enum ITermVersion: String, CaseIterable, Identifiable, Hashable {
    case stable
    case nightly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stable: "Stable"
        case .nightly: "Nightly"
        }
    }
}

/// Mirrors the per-command `inTerminal` key and the global `open_in` key.
enum TerminalWindowMode: String, CaseIterable, Identifiable, Hashable {
    case tab
    case new
    case current
    case virtual

    var id: String { rawValue }

    /// The two values `open_in` accepts; anything else is coerced to `tab`.
    static let globalDefaults: [TerminalWindowMode] = [.tab, .new]

    /// Localized here rather than in the views, because it is also interpolated
    /// into text and `Text(String)` would not be localized.
    var displayName: String {
        switch self {
        case .tab: String(localized: "New tab in the active window")
        case .new: String(localized: "New window")
        case .current: String(localized: "Current window")
        case .virtual: String(localized: "New window with a virtual screen")
        }
    }
}

// MARK: - Menu name decorations

/// A menu title and the one marker Shuttle still encodes inside it.
///
/// Shuttle strips `[---]` from a title before displaying it and inserts a
/// separator after the entry instead. Editing that part separately keeps the
/// user from typing brackets by hand.
///
/// Titles used to be able to carry a `[abc]` sort marker as well, because every
/// menu was sorted alphabetically. Menus now follow the order of the entries in
/// the file, so that marker is dropped when a title is read.
struct MenuItemName: Hashable, Sendable {
    /// The title as shown in the menu, with all markers removed.
    var text: String = ""
    /// Whether a separator follows this entry in the menu.
    var addsSeparator: Bool = false

    init(text: String = "", addsSeparator: Bool = false) {
        self.text = text
        self.addsSeparator = addsSeparator
    }

    init(raw: String) {
        // Built locally: `Regex` is not Sendable, so it cannot be a static.
        let legacySortMarker = /\[[a-z]{3}\]/
        let separatorMarker = /\[-{3}\]/

        var remainder = raw

        if let match = remainder.firstMatch(of: legacySortMarker) {
            remainder.removeSubrange(match.range)
        }

        if let match = remainder.firstMatch(of: separatorMarker) {
            addsSeparator = true
            remainder.removeSubrange(match.range)
        }

        text = remainder.trimmingCharacters(in: .whitespaces)
    }

    /// The string written back to JSON.
    var raw: String {
        addsSeparator ? text + "[---]" : text
    }
}

// MARK: - Hosts tree

/// A command entry: one clickable item in the status menu.
struct HostCommand: Hashable, Sendable {
    var cmd: String = ""
    /// `nil` means "use the global `open_in` setting".
    var inTerminal: TerminalWindowMode?
    /// Empty means "use the global `default_theme` setting".
    var theme: String = ""
    /// Empty means "use the menu title".
    var title: String = ""
    /// Keys of this entry the editor does not model.
    var extras: [String: JSONValue] = [:]
}

/// One node of the `hosts` tree: either a command or a submenu of children.
struct HostNode: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case command(HostCommand)
        case group([HostNode])
    }

    let id: UUID
    var name: MenuItemName
    var kind: Kind

    init(id: UUID = UUID(), name: MenuItemName, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    var children: [HostNode]? {
        if case .group(let children) = kind { children } else { nil }
    }

    var isGroup: Bool { children != nil }

    var command: HostCommand? {
        if case .command(let command) = kind { command } else { nil }
    }

    static func newCommand() -> HostNode {
        HostNode(name: MenuItemName(text: "New Command"), kind: .command(HostCommand(cmd: "ssh user@host")))
    }

    static func newGroup() -> HostNode {
        HostNode(name: MenuItemName(text: "New Group"), kind: .group([]))
    }
}

// MARK: - Global settings

struct GlobalSettings: Hashable, Sendable {
    var terminal: TerminalApp = .terminal
    var iTermVersion: ITermVersion = .nightly
    /// "default" opens the file with the system handler; anything else is run as
    /// a terminal command, e.g. "nano" or "vi".
    var editor: String = "default"
    var defaultTheme: String = ""
    var openIn: TerminalWindowMode = .tab
    var launchAtLogin: Bool = false
    /// Shuttle defaults this to true when the key is absent.
    var showSSHConfigHosts: Bool = true
    var sshConfigIgnoreHosts: [String] = []
    var sshConfigIgnoreKeywords: [String] = []
}

// MARK: - Document

struct ShuttleConfiguration: Hashable, Sendable {
    var settings = GlobalSettings()
    var hosts: [HostNode] = []
    /// Top-level keys the editor does not model, "_comments" included.
    var preservedKeys: [String: JSONValue] = [:]

    static let modelledTopLevelKeys: Set<String> = [
        "terminal", "iTerm_version", "editor", "default_theme", "open_in",
        "launch_at_login", "show_ssh_config_hosts",
        "ssh_config_ignore_hosts", "ssh_config_ignore_keywords", "hosts",
    ]
}

// MARK: - Decoding

extension ShuttleConfiguration {
    enum DecodingFailure: LocalizedError {
        case notAnObject

        var errorDescription: String? {
            switch self {
            case .notAnObject: String(localized: "The configuration file is not a JSON object.")
            }
        }
    }

    init(data: Data) throws {
        let parsed = try JSONSerialization.jsonObject(with: data)
        guard let root = parsed as? [String: Any] else { throw DecodingFailure.notAnObject }

        var settings = GlobalSettings()
        if let value = root["terminal"] as? String {
            // Match AppDelegate's case-insensitive comparison.
            settings.terminal = TerminalApp.allCases.first { $0.rawValue.lowercased() == value.lowercased() } ?? .terminal
        }
        if let value = root["iTerm_version"] as? String {
            settings.iTermVersion = ITermVersion(rawValue: value.lowercased()) ?? .nightly
        }
        if let value = root["editor"] as? String {
            settings.editor = value
        }
        if let value = root["default_theme"] as? String {
            settings.defaultTheme = value
        }
        if let value = root["open_in"] as? String {
            let mode = TerminalWindowMode(rawValue: value.lowercased()) ?? .tab
            settings.openIn = TerminalWindowMode.globalDefaults.contains(mode) ? mode : .tab
        }
        settings.launchAtLogin = (root["launch_at_login"] as? NSNumber)?.boolValue ?? false
        settings.showSSHConfigHosts = (root["show_ssh_config_hosts"] as? NSNumber)?.boolValue ?? true
        settings.sshConfigIgnoreHosts = (root["ssh_config_ignore_hosts"] as? [Any])?.compactMap { $0 as? String } ?? []
        settings.sshConfigIgnoreKeywords = (root["ssh_config_ignore_keywords"] as? [Any])?.compactMap { $0 as? String } ?? []

        self.settings = settings
        self.hosts = Self.decodeNodes(root["hosts"] as? [Any] ?? [])
        self.preservedKeys = root
            .filter { !Self.modelledTopLevelKeys.contains($0.key) }
            .compactMapValues(JSONValue.init)
    }

    private static func decodeNodes(_ raw: [Any]) -> [HostNode] {
        var nodes: [HostNode] = []

        for element in raw {
            guard let entry = element as? [String: Any] else { continue }

            if entry["cmd"] != nil || entry["name"] != nil {
                nodes.append(decodeCommand(entry))
            } else {
                // A submenu. Shuttle iterates every key of the dictionary, so a
                // multi-key dictionary yields one group per key.
                for key in entry.keys.sorted() {
                    guard let children = entry[key] as? [Any] else { continue }
                    nodes.append(HostNode(name: MenuItemName(raw: key), kind: .group(decodeNodes(children))))
                }
            }
        }

        return nodes
    }

    private static func decodeCommand(_ entry: [String: Any]) -> HostNode {
        var command = HostCommand()
        command.cmd = entry["cmd"] as? String ?? ""
        command.theme = entry["theme"] as? String ?? ""
        command.title = entry["title"] as? String ?? ""
        if let value = entry["inTerminal"] as? String {
            command.inTerminal = TerminalWindowMode(rawValue: value.lowercased())
        }
        command.extras = entry
            .filter { !["cmd", "name", "theme", "title", "inTerminal"].contains($0.key) }
            .compactMapValues(JSONValue.init)

        return HostNode(name: MenuItemName(raw: entry["name"] as? String ?? ""), kind: .command(command))
    }
}

// MARK: - Encoding

extension ShuttleConfiguration {
    /// The JSON object written to disk, with preserved keys merged back in.
    var jsonObject: [String: Any] {
        var root: [String: Any] = preservedKeys.mapValues(\.anyValue)

        root["terminal"] = settings.terminal.rawValue
        root["iTerm_version"] = settings.iTermVersion.rawValue
        root["editor"] = settings.editor
        root["default_theme"] = settings.defaultTheme
        root["open_in"] = settings.openIn.rawValue
        root["launch_at_login"] = settings.launchAtLogin
        root["show_ssh_config_hosts"] = settings.showSSHConfigHosts
        root["ssh_config_ignore_hosts"] = settings.sshConfigIgnoreHosts
        root["ssh_config_ignore_keywords"] = settings.sshConfigIgnoreKeywords
        root["hosts"] = Self.encodeNodes(hosts)

        return root
    }

    func encoded() throws -> Data {
        try JSONSerialization.data(
            withJSONObject: jsonObject,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    private static func encodeNodes(_ nodes: [HostNode]) -> [Any] {
        nodes.map { node in
            switch node.kind {
            case .group(let children):
                return [node.name.raw: encodeNodes(children)]

            case .command(let command):
                var entry: [String: Any] = command.extras.mapValues(\.anyValue)
                entry["name"] = node.name.raw
                entry["cmd"] = command.cmd
                if let inTerminal = command.inTerminal {
                    entry["inTerminal"] = inTerminal.rawValue
                }
                if !command.theme.isEmpty {
                    entry["theme"] = command.theme
                }
                if !command.title.isEmpty {
                    entry["title"] = command.title
                }
                return entry
            }
        }
    }
}

// MARK: - Tree editing

extension Array<HostNode> {
    func node(id: UUID) -> HostNode? {
        for node in self {
            if node.id == id { return node }
            if let children = node.children, let found = children.node(id: id) { return found }
        }
        return nil
    }

    /// Applies `body` to the node with the given id, at any depth.
    @discardableResult
    mutating func updateNode(id: UUID, _ body: (inout HostNode) -> Void) -> Bool {
        for index in indices {
            if self[index].id == id {
                body(&self[index])
                return true
            }
            if case .group(var children) = self[index].kind {
                if children.updateNode(id: id, body) {
                    self[index].kind = .group(children)
                    return true
                }
            }
        }
        return false
    }

    @discardableResult
    mutating func removeNode(id: UUID) -> HostNode? {
        for index in indices {
            if self[index].id == id {
                return remove(at: index)
            }
            if case .group(var children) = self[index].kind {
                if let removed = children.removeNode(id: id) {
                    self[index].kind = .group(children)
                    return removed
                }
            }
        }
        return nil
    }

    /// Appends `nodes` to the group with the given id, or to the root when `nil`.
    @discardableResult
    mutating func appendNodes(_ nodes: [HostNode], toGroup groupID: UUID?) -> Bool {
        guard let groupID else {
            append(contentsOf: nodes)
            return true
        }
        return updateNode(id: groupID) { parent in
            if case .group(var children) = parent.kind {
                children.append(contentsOf: nodes)
                parent.kind = .group(children)
            }
        }
    }

    @discardableResult
    mutating func appendNode(_ node: HostNode, toGroup groupID: UUID?) -> Bool {
        appendNodes([node], toGroup: groupID)
    }

    /// Inserts `nodes` ahead of every other child of the group with the given id.
    @discardableResult
    mutating func prependNodes(_ nodes: [HostNode], toGroup groupID: UUID) -> Bool {
        updateNode(id: groupID) { parent in
            if case .group(var children) = parent.kind {
                children.insert(contentsOf: nodes, at: children.startIndex)
                parent.kind = .group(children)
            }
        }
    }

    /// Inserts `nodes` right after the node with the given id, at any depth, so
    /// they become its next siblings.
    @discardableResult
    mutating func insertNodes(_ nodes: [HostNode], after id: UUID) -> Bool {
        for index in indices {
            if self[index].id == id {
                insert(contentsOf: nodes, at: index + 1)
                return true
            }
            if case .group(var children) = self[index].kind {
                if children.insertNodes(nodes, after: id) {
                    self[index].kind = .group(children)
                    return true
                }
            }
        }
        return false
    }

    /// Moves the sources of a drag so they land right after `anchorID`: as its
    /// first children when `inside` is true (the anchor is an open submenu),
    /// otherwise as its next siblings. A `nil` anchor means the top of the menu.
    mutating func moveNodes(ids: [UUID], after anchorID: UUID?, inside: Bool) {
        // Nothing can be dropped into itself or into its own subtree, and the
        // anchor must survive the removal below for its position to be found.
        let sources = ids.filter { id in
            guard let anchorID else { return true }
            return id != anchorID && !isDescendant(anchorID, of: id)
        }
        guard !sources.isEmpty else { return }

        let moved = sources.compactMap { removeNode(id: $0) }
        guard !moved.isEmpty else { return }

        guard let anchorID else {
            insert(contentsOf: moved, at: startIndex)
            return
        }

        let inserted = inside
            ? prependNodes(moved, toGroup: anchorID)
            : insertNodes(moved, after: anchorID)

        // The anchor is gone, which only happens if it was dragged along: keep
        // the entries rather than dropping them on the floor.
        if !inserted {
            append(contentsOf: moved)
        }
    }

    /// Moves the sources of a drag to the end of the top-level menu.
    mutating func moveNodesToEnd(ids: [UUID]) {
        let moved = ids.compactMap { removeNode(id: $0) }
        append(contentsOf: moved)
    }

    /// Swaps a node with the sibling `offset` positions away. `false` means the
    /// node is already at that end of its menu.
    @discardableResult
    mutating func moveNode(id: UUID, by offset: Int) -> Bool {
        for index in indices {
            if self[index].id == id {
                let target = index + offset
                guard indices.contains(target) else { return false }
                swapAt(index, target)
                return true
            }
            if case .group(var children) = self[index].kind {
                if children.moveNode(id: id, by: offset) {
                    self[index].kind = .group(children)
                    return true
                }
            }
        }
        return false
    }

    /// The menu a node belongs to, including the node itself.
    func siblings(of id: UUID) -> [HostNode] {
        guard let parentID = parentID(of: id) else { return self }
        return node(id: parentID)?.children ?? []
    }

    /// Sorts the children of a group (the root when `nil`) the way Shuttle's
    /// menus used to be ordered: submenus first, then commands, each by name.
    mutating func sortNodes(inGroup groupID: UUID?, recursively: Bool) {
        guard let groupID else {
            sortForMenu(recursively: recursively)
            return
        }
        updateNode(id: groupID) { parent in
            if case .group(var children) = parent.kind {
                children.sortForMenu(recursively: recursively)
                parent.kind = .group(children)
            }
        }
    }

    private mutating func sortForMenu(recursively: Bool) {
        sort { lhs, rhs in
            if lhs.isGroup != rhs.isGroup { return lhs.isGroup }
            return lhs.name.text.localizedStandardCompare(rhs.name.text) == .orderedAscending
        }

        guard recursively else { return }
        for index in indices {
            if case .group(var children) = self[index].kind {
                children.sortForMenu(recursively: true)
                self[index].kind = .group(children)
            }
        }
    }

    func parentID(of id: UUID) -> UUID? {
        for node in self {
            guard let children = node.children else { continue }
            if children.contains(where: { $0.id == id }) { return node.id }
            if let deeper = children.parentID(of: id) { return deeper }
        }
        return nil
    }

    /// Every group in the tree, with a "Parent ▸ Child" path for menu display.
    func groupPaths(prefix: String = "") -> [(id: UUID, path: String)] {
        var result: [(id: UUID, path: String)] = []
        for node in self {
            guard let children = node.children else { continue }
            let path = prefix.isEmpty ? node.name.text : "\(prefix) ▸ \(node.name.text)"
            result.append((node.id, path))
            result.append(contentsOf: children.groupPaths(prefix: path))
        }
        return result
    }

    /// Whether `descendantID` lives anywhere under `ancestorID`, used to stop a
    /// group from being moved into itself.
    func isDescendant(_ descendantID: UUID, of ancestorID: UUID) -> Bool {
        guard let ancestor = node(id: ancestorID), let children = ancestor.children else { return false }
        return children.node(id: descendantID) != nil
    }

    /// A deep copy with fresh identities, so a duplicated subtree stays editable.
    func reidentified() -> [HostNode] {
        map { node in
            switch node.kind {
            case .command(let command):
                HostNode(name: node.name, kind: .command(command))
            case .group(let children):
                HostNode(name: node.name, kind: .group(children.reidentified()))
            }
        }
    }
}
