//
//  ShuttleAboutWindow.swift
//  Shuttle
//
//  The About window: the app icon, the name and tagline, the version, a link to
//  the project page and the copyright notice.
//
//  Replaces the old AboutWindowController.xib, whose fixed 460×172 layout clipped
//  the copyright notice onto one truncated line.
//

import AppKit
import SwiftUI

@objc(ShuttleAboutWindow)
public final class ShuttleAboutWindow: NSObject {
    private static var windowController: ShuttleAboutWindowController?

    /// Opens the About window, or brings the existing one to the front.
    @objc(showAboutWindow)
    public static func show() {
        let controller = windowController ?? {
            let controller = ShuttleAboutWindowController()
            controller.onClose = { windowController = nil }
            windowController = controller
            return controller
        }()

        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

// MARK: - Window

private final class ShuttleAboutWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (@MainActor () -> Void)?

    init() {
        let hostingController = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: hostingController)

        window.styleMask = [.titled, .closable, .fullSizeContentView]
        // An About panel carries no title bar of its own; the content is the
        // window, and dragging anywhere in it moves the window.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = String(format: NSLocalizedString("About %@", comment: "About window title"), Self.appName)
        // Shuttle is a status-bar app, so the window stays above other apps.
        window.level = .floating

        super.init(window: window)

        window.delegate = self
        shouldCascadeWindows = false
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    static var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Shuttle"
    }
}

// MARK: - Content

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSImage(named: "shuttle") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            Text(appName)
                .font(.system(.title, design: .default, weight: .semibold))
                .padding(.top, 10)

            Text(tagline)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)

            Text(version)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .padding(.top, 10)

            if let homepage {
                Link(destination: homepage) {
                    Label("Homepage", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .padding(.top, 18)
            }

            Divider()
                .padding(.top, 20)

            // One line per copyright holder: the whole notice on a single line
            // is wider than any reasonable window.
            VStack(spacing: 2) {
                ForEach(copyrightLines, id: \.self) { line in
                    Text(line)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
        }
        .padding(.horizontal, 30)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(width: 360)
    }

    // MARK: Bundle values

    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    private var appName: String {
        info["CFBundleName"] as? String ?? "Shuttle"
    }

    /// The tagline is stored with the " - " that used to join it to the app
    /// name; the two are stacked now, so the separator is dropped.
    private var tagline: String {
        String(localized: " - A simple SSH shortcut menu.")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -"))
    }

    private var version: String {
        let number = info["CFBundleShortVersionString"] as? String
            ?? info["CFBundleVersion"] as? String
            ?? ""
        return String(localized: "Version: ") + number
    }

    private var homepage: URL? {
        (info["Product Homepage"] as? String).flatMap(URL.init(string:))
    }

    private var copyrightLines: [String] {
        let notice = info["NSHumanReadableCopyright"] as? String ?? ""
        let lines = notice
            .split(separator: /\s+(?=Copyright)/)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        return lines.isEmpty ? [notice] : lines
    }
}

#Preview("About") {
    AboutView()
}
