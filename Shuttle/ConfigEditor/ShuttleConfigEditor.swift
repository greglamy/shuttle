//
//  ShuttleConfigEditor.swift
//  Shuttle
//
//  Hosts ConfigEditorView in a real window and exposes a single entry point to
//  AppDelegate.
//
//  Shuttle is an LSUIElement app with no main menu, so two things have to be
//  arranged before a window full of text fields is usable: the app needs a
//  regular activation policy to take focus properly, and it needs a menu with
//  the standard editing key equivalents, otherwise ⌘C / ⌘V / ⌘Z do nothing.
//  Both are set up while the editor is open and undone when it closes.
//

import AppKit
import SwiftUI

@objc(ShuttleConfigEditor)
public final class ShuttleConfigEditor: NSObject {
    private static var windowController: ShuttleConfigEditorWindowController?

    /// Opens the editor for the configuration file at `path`, or brings the
    /// existing window to the front.
    @objc(showEditorForConfigAtPath:)
    public static func showEditor(configAtPath path: String) {
        if let existing = windowController {
            // Picking up outside edits is safe as long as nothing is pending.
            if !existing.store.isDirty, existing.store.fileChangedOutsideEditor {
                existing.store.load()
            }
            existing.present()
            return
        }

        let store = ShuttleConfigStore(fileURL: URL(fileURLWithPath: path))
        let controller = ShuttleConfigEditorWindowController(store: store)
        controller.onClose = { windowController = nil }
        windowController = controller
        controller.present()
    }
}

// MARK: - Window

final class ShuttleConfigEditorWindowController: NSWindowController, NSWindowDelegate {
    let store: ShuttleConfigStore

    var onClose: (@MainActor () -> Void)?

    private var previousActivationPolicy: NSApplication.ActivationPolicy?
    private var installedMenu: NSMenu?

    init(store: ShuttleConfigStore) {
        self.store = store

        let hostingController = NSHostingController(rootView: ConfigEditorView(store: store))
        let window = NSWindow(contentViewController: hostingController)
        window.title = NSLocalizedString("Shuttle Configuration", comment: "Editor window title")
        window.setContentSize(NSSize(width: 900, height: 580))
        window.minSize = NSSize(width: 720, height: 440)

        super.init(window: window)

        window.delegate = self
        shouldCascadeWindows = false
        windowFrameAutosaveName = "ShuttleConfigEditorWindow"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        installEditingMenuIfNeeded()

        if previousActivationPolicy == nil {
            previousActivationPolicy = NSApp.activationPolicy()
            NSApp.setActivationPolicy(.regular)
        }

        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard store.isDirty else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Save the changes to your configuration?", comment: "")
        alert.informativeText = NSLocalizedString("Your changes will be lost if you don't save them.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Save", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Don't Save", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            do {
                try store.save()
                return true
            } catch {
                let failure = NSAlert(error: error)
                failure.runModal()
                return false
            }
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let previousActivationPolicy {
            NSApp.setActivationPolicy(previousActivationPolicy)
            self.previousActivationPolicy = nil
        }

        if let installedMenu, NSApp.mainMenu === installedMenu {
            NSApp.mainMenu = nil
            self.installedMenu = nil
        }

        onClose?()
    }

    // MARK: Main menu

    /// Builds the minimum menu bar a text-editing window needs. Left alone if
    /// the app already has a main menu.
    private func installEditingMenuIfNeeded() {
        guard NSApp.mainMenu == nil else { return }

        let appName = ProcessInfo.processInfo.processName
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: String(format: NSLocalizedString("About %@", comment: "App menu"), appName),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: String(format: NSLocalizedString("Hide %@", comment: "App menu"), appName),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(
            withTitle: String(format: NSLocalizedString("Quit %@", comment: "App menu"), appName),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: NSLocalizedString("Edit", comment: "Menu bar"))
        editMenu.addItem(withTitle: NSLocalizedString("Undo", comment: ""), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: NSLocalizedString("Redo", comment: ""), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: NSLocalizedString("Cut", comment: ""), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: NSLocalizedString("Copy", comment: ""), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: NSLocalizedString("Paste", comment: ""), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: NSLocalizedString("Select All", comment: ""), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: NSLocalizedString("Window", comment: "Menu bar"))
        windowMenu.addItem(
            withTitle: NSLocalizedString("Close", comment: ""),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
        installedMenu = mainMenu
    }
}
