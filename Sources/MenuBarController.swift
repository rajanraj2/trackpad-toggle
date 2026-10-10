// MenuBarController.swift
// Manages the NSStatusItem (menu bar icon + menu) and wires state changes to UI.

import AppKit
import os.log

private let logger = Logger(subsystem: "com.powertools.trackpadtoggle", category: "MenuBar")

final class MenuBarController {

    private let statusItem: NSStatusItem
    private weak var controller: (any TrackpadControlling)?

    // Strong ref to the settings window controller so it isn't deallocated on close.
    private var settingsWC: SettingsWindowController?

    init(controller: any TrackpadControlling) {
        self.controller = controller
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        updateVisibility()
        rebuildMenu()
        controller.onStateChange = { [weak self] _ in
            DispatchQueue.main.async { self?.rebuildMenu() }
        }

        UpdateManager.shared.onStatusChange = { [weak self] _ in
            DispatchQueue.main.async { self?.rebuildMenu() }
        }
    }

    // MARK: – Button

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "hand.point.up.left.fill",
                               accessibilityDescription: "Trackpad Toggle")
        button.image?.isTemplate = true  // respects menu bar tint
    }

    // MARK: – Menu

    func rebuildMenu() {
        let menu = NSMenu()
        let state = controller?.state ?? .enabled

        // ── Status header (non-clickable) ─────────────────────────────────────
        let statusItem = NSMenuItem(title: state.displayTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        if let logo = loadSmallLogo() {
            statusItem.image = logo
        }
        menu.addItem(statusItem)
        // ── Single Consolidated Version & Update Line ────────────────────────
        let currentVer = UpdateManager.shared.currentVersion
        let versionItem: NSMenuItem
        if case .updateAvailable(let newVer, _, _, _) = UpdateManager.shared.status {
            // Update available: Shows both versions on the same line with "Click to Update" action
            versionItem = NSMenuItem(
                title: "v\(currentVer) → v\(newVer)  (Click to Update)",
                action: #selector(AppDelegate.promptUpdate),
                keyEquivalent: ""
            )
            versionItem.target = NSApp.delegate
            versionItem.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Update Available")
        } else {
            // Latest version: Clean display of installed version, NO update button or update text
            versionItem = NSMenuItem(
                title: "Trackpad Toggle v\(currentVer)  (Latest)",
                action: #selector(AppDelegate.checkForUpdatesManual),
                keyEquivalent: ""
            )
            versionItem.target = NSApp.delegate
            versionItem.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Up to date")
        }
        menu.addItem(versionItem)
        // Permissions warning banner
        if state == .permissionRequired {
            menu.addItem(.separator())
            let warn = NSMenuItem(title: "⚠️ Grant Accessibility Access…",
                                  action: #selector(AppDelegate.grantAccessibility),
                                  keyEquivalent: "")
            warn.target = NSApp.delegate
            menu.addItem(warn)
            let warn2 = NSMenuItem(title: "⚠️ Grant Input Monitoring…",
                                   action: #selector(AppDelegate.grantInputMonitoring),
                                   keyEquivalent: "")
            warn2.target = NSApp.delegate
            menu.addItem(warn2)
        }

        menu.addItem(.separator())

        // ── Toggle action ──────────────────────────────────────────────────────
        let toggleTitle: String
        switch state {
        case .enabled:  toggleTitle = "Disable Trackpad"
        case .disabled: toggleTitle = "Enable Trackpad"
        default:        toggleTitle = "Toggle Trackpad"
        }
        let shortcut = Preferences.shared.hotKeyDescription
        let toggleItem = NSMenuItem(title: "\(toggleTitle)  (\(shortcut))",
                                    action: #selector(AppDelegate.toggleTrackpad),
                                    keyEquivalent: "")
        toggleItem.target = NSApp.delegate
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        // ── Direct Quick Actions: Shortcut & Startup ──────────────────────────
        let changeShortcutItem = NSMenuItem(title: "Change Shortcut…",
                                            action: #selector(AppDelegate.changeShortcut),
                                            keyEquivalent: "")
        changeShortcutItem.target = NSApp.delegate
        menu.addItem(changeShortcutItem)

        let launchAtLoginItem = NSMenuItem(title: "Launch at Login",
                                           action: #selector(AppDelegate.toggleLaunchAtLogin),
                                           keyEquivalent: "")
        launchAtLoginItem.target = NSApp.delegate
        launchAtLoginItem.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        let blockItem = NSMenuItem(title: "Block Cursor & Gestures",
                                   action: #selector(AppDelegate.toggleBlockCursorAndGestures),
                                   keyEquivalent: "")
        blockItem.target = NSApp.delegate
        blockItem.state = Preferences.shared.blockCursorAndGestures ? .on : .off
        menu.addItem(blockItem)

        menu.addItem(.separator())

        // ── Settings ──────────────────────────────────────────────────────────
        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(AppDelegate.openSettings),
                                      keyEquivalent: ",")
        settingsItem.target = NSApp.delegate
        menu.addItem(settingsItem)

        // ── Quit ──────────────────────────────────────────────────────────────
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Trackpad Toggle",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        self.statusItem.menu = menu
        updateIcon(for: state)
    }

    private func updateIcon(for state: TrackpadState) {
        guard let button = self.statusItem.button else { return }
        button.image = NSImage(systemSymbolName: state.menuBarSymbol,
                               accessibilityDescription: state.displayTitle)
        button.image?.isTemplate = true
    }

    func updateVisibility() {
        statusItem.isVisible = Preferences.shared.showMenuBarIcon
    }

    private func loadSmallLogo() -> NSImage? {
        let icon: NSImage?
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns") {
            icon = NSImage(contentsOfFile: path)
        } else if let path = Bundle.main.path(forResource: "AppIcon", ofType: "png") {
            icon = NSImage(contentsOfFile: path)
        } else {
            icon = NSImage(named: NSImage.applicationIconName)
        }
        guard let img = icon else { return nil }
        let copy = img.copy() as! NSImage
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }
    // MARK: – Settings window

    func showSettings(focusShortcut: Bool = false) {
        if settingsWC == nil {
            settingsWC = SettingsWindowController()
        }
        if focusShortcut {
            settingsWC?.startRecordingShortcut()
        }
        settingsWC?.showWindow(nil)
        settingsWC?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
