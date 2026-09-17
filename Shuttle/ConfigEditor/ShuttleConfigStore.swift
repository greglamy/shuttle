//
//  ShuttleConfigStore.swift
//  Shuttle
//
//  Owns the in-memory configuration for the editor window: loading, saving,
//  dirty tracking and the validation warnings shown in the UI.
//

import Foundation
import Observation

@Observable
final class ShuttleConfigStore {
    /// A problem worth surfacing, but never blocking a save.
    struct Warning: Identifiable, Hashable {
        let id = UUID()
        let message: String
        /// The node the warning points at, when it has one.
        let nodeID: UUID?
    }

    let fileURL: URL

    var configuration: ShuttleConfiguration

    /// The last state written to (or read from) disk, used for dirty tracking.
    private var savedConfiguration: ShuttleConfiguration

    /// Modification date seen at load time, used to detect outside edits.
    private var lastKnownModificationDate: Date?

    /// Set when the file could not be read or parsed.
    private(set) var loadFailure: String?

    var isDirty: Bool { configuration != savedConfiguration }

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.configuration = ShuttleConfiguration()
        self.savedConfiguration = ShuttleConfiguration()
        load()
    }

    // MARK: Disk

    func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            configuration = try ShuttleConfiguration(data: data)
            savedConfiguration = configuration
            loadFailure = nil
        } catch {
            // Keep the empty document so the window still opens and explains itself.
            loadFailure = error.localizedDescription
        }
        lastKnownModificationDate = currentModificationDate()
    }

    func save() throws {
        let data = try configuration.encoded()
        try data.write(to: fileURL, options: .atomic)
        savedConfiguration = configuration
        lastKnownModificationDate = currentModificationDate()
    }

    func revert() {
        configuration = savedConfiguration
    }

    /// True when something else wrote the file since we last read or wrote it.
    var fileChangedOutsideEditor: Bool {
        guard let lastKnownModificationDate, let current = currentModificationDate() else { return false }
        return current > lastKnownModificationDate
    }

    private func currentModificationDate() -> Date? {
        try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
    }

    // MARK: Editing

    func node(id: UUID) -> HostNode? {
        configuration.hosts.node(id: id)
    }

    func update(id: UUID, _ body: (inout HostNode) -> Void) {
        configuration.hosts.updateNode(id: id, body)
    }

    /// Inserts a new node inside `groupID`, or at the root when it is `nil`.
    /// Returns the id so the caller can select the new row.
    @discardableResult
    func add(_ node: HostNode, toGroup groupID: UUID?) -> UUID {
        configuration.hosts.appendNode(node, toGroup: groupID)
        return node.id
    }

    /// The group a new entry should land in for the current selection: the
    /// selected group itself, or the parent of the selected command.
    func insertionTarget(for selectedID: UUID?) -> UUID? {
        guard let selectedID, let node = node(id: selectedID) else { return nil }
        return node.isGroup ? node.id : configuration.hosts.parentID(of: selectedID)
    }

    func remove(id: UUID) {
        configuration.hosts.removeNode(id: id)
    }

    @discardableResult
    func duplicate(id: UUID) -> UUID? {
        guard let original = node(id: id) else { return nil }

        let copyName = MenuItemName(
            text: original.name.text + " copy",
            addsSeparator: original.name.addsSeparator
        )
        let copy: HostNode = switch original.kind {
        case .command(let command): HostNode(name: copyName, kind: .command(command))
        case .group(let children): HostNode(name: copyName, kind: .group(children.reidentified()))
        }

        configuration.hosts.insertNodes([copy], after: id)
        return copy.id
    }

    /// Moves a node into another group. A group cannot be moved into itself or
    /// into one of its own descendants.
    func move(id: UUID, toGroup groupID: UUID?) {
        guard id != groupID else { return }
        if let groupID, configuration.hosts.isDescendant(groupID, of: id) { return }
        guard let moved = configuration.hosts.removeNode(id: id) else { return }
        configuration.hosts.appendNode(moved, toGroup: groupID)
    }

    // MARK: Ordering

    /// Applies a drag: `ids` land right after `anchorID`, inside it when it is
    /// an open submenu. Menus follow the order of the entries, so this is what
    /// sets the position of a command or a submenu in the Shuttle menu.
    func reorder(ids: [UUID], after anchorID: UUID?, inside: Bool) {
        configuration.hosts.moveNodes(ids: ids, after: anchorID, inside: inside)
    }

    /// Applies a drag that landed ahead of `beforeID`: that row keeps its place
    /// in its own menu and the dragged entries take the slot in front of it.
    func reorder(ids: [UUID], before beforeID: UUID) {
        let moving = Set(ids)
        let siblings = configuration.hosts.siblings(of: beforeID)
        guard let index = siblings.firstIndex(where: { $0.id == beforeID }) else { return }

        // The dragged entries land after the closest row above the drop that is
        // not itself being dragged, or at the top of the menu when there is
        // none: an entry dragged just above the one that already follows it
        // therefore stays where it is instead of being lost.
        if let anchor = siblings[..<index].last(where: { !moving.contains($0.id) }) {
            reorder(ids: ids, after: anchor.id, inside: false)
        } else {
            let parentID = configuration.hosts.parentID(of: beforeID)
            reorder(ids: ids, after: parentID, inside: parentID != nil)
        }
    }

    /// Applies a drag that landed past the last row: `ids` go to the end of the
    /// top-level menu.
    func reorderToEnd(ids: [UUID]) {
        configuration.hosts.moveNodesToEnd(ids: ids)
    }

    /// Moves a node one step up or down among its siblings.
    func move(id: UUID, by offset: Int) {
        configuration.hosts.moveNode(id: id, by: offset)
    }

    /// Whether `move(id:by:)` would do anything, used to disable the commands.
    func canMove(id: UUID, by offset: Int) -> Bool {
        let siblings = configuration.hosts.siblings(of: id)
        guard let index = siblings.firstIndex(where: { $0.id == id }) else { return false }
        return siblings.indices.contains(index + offset)
    }

    /// Sorts a submenu (the whole menu when `groupID` is `nil`) by name.
    func sort(group groupID: UUID?, recursively: Bool = false) {
        configuration.hosts.sortNodes(inGroup: groupID, recursively: recursively)
    }

    /// Groups that `id` can be moved into, excluding its own subtree and its
    /// current parent.
    func moveDestinations(for id: UUID) -> [(id: UUID?, path: String)] {
        let currentParent = configuration.hosts.parentID(of: id)
        var destinations: [(id: UUID?, path: String)] = []

        if currentParent != nil {
            destinations.append((nil, String(localized: "Top Level")))
        }

        for group in configuration.hosts.groupPaths()
        where group.id != id && group.id != currentParent && !configuration.hosts.isDescendant(group.id, of: id) {
            destinations.append((group.id, group.path))
        }

        return destinations
    }

    // MARK: Validation

    /// Non-blocking warnings about things Shuttle would silently ignore.
    var warnings: [Warning] {
        var result: [Warning] = []
        collectWarnings(in: configuration.hosts, path: "", into: &result)

        if configuration.settings.editor.isEmpty {
            result.append(Warning(message: String(localized: "The text editor field is empty; use \"default\" to open the file with the system handler."), nodeID: nil))
        }

        return result
    }

    private func collectWarnings(in nodes: [HostNode], path: String, into result: inout [Warning]) {
        for node in nodes {
            let label = path.isEmpty ? node.name.text : "\(path) ▸ \(node.name.text)"

            if node.name.text.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append(Warning(message: String(localized: "An entry has no name and will not appear in the menu."), nodeID: node.id))
            }

            switch node.kind {
            case .command(let command):
                if command.cmd.trimmingCharacters(in: .whitespaces).isEmpty {
                    result.append(Warning(
                        message: String(localized: "\"\(label)\" has no command to run."),
                        nodeID: node.id
                    ))
                }
            case .group(let children):
                if children.isEmpty {
                    result.append(Warning(
                        message: String(localized: "\"\(label)\" is an empty group and will show as an empty submenu."),
                        nodeID: node.id
                    ))
                }
                collectWarnings(in: children, path: label, into: &result)
            }
        }
    }
}
