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
        menu.addItem(statusItem)

        // ── Update Notification Banner ────────────────────────────────────────
        if case .updateAvailable(let newVer, _, _, _) = UpdateManager.shared.status {
            menu.addItem(.separator())
            let updateItem = NSMenuItem(
                title: "⭐️ Update Available: v\(newVer) (Click to Upgrade)",
                action: #selector(AppDelegate.promptUpdate),
                keyEquivalent: ""
            )
            updateItem.target = NSApp.delegate
            menu.addItem(updateItem)
        }
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

        let checkUpdateItem = NSMenuItem(title: "Check for Updates…",
                                         action: #selector(AppDelegate.checkForUpdatesManual),
                                         keyEquivalent: "")
        checkUpdateItem.target = NSApp.delegate
        menu.addItem(checkUpdateItem)

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
