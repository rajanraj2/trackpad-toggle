// AppDelegate.swift
// Application entry point and coordinator.
// Wires: TrackpadController ↔ HotKeyManager ↔ MenuBarController.

import AppKit
import os.log

private let logger = Logger(subsystem: "com.powertools.trackpadtoggle", category: "AppDelegate")

final class AppDelegate: NSObject, NSApplicationDelegate {

    // Exposed so SettingsView can read state without a global.
    private(set) var trackpadController: (any TrackpadControlling)!
    private(set) var menuBarController: MenuBarController?

    // MARK: – Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("TrackpadToggle launched — macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

        // 1. Build the trackpad controller.
        trackpadController = CGEventTapController()

        // 2. Wire the menu bar.
        let mbc = MenuBarController(controller: trackpadController)
        menuBarController = mbc

        // 3. Register the Carbon hotkey.
        HotKeyManager.shared.onHotKey = { [weak self] in
            self?.toggleTrackpad()
        }
        HotKeyManager.shared.register()

        // 4. Observe sleep/wake so we can reinstall the tap after wakeup.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // 5. Check permissions on launch and show a banner if missing.
        if !PermissionsManager.shared.hasAccessibility {
            trackpadController.onStateChange?(.permissionRequired)
            showPermissionAlert()
        }

        logger.info("Startup complete. Shortcut: \(Preferences.shared.hotKeyDescription)")
    }

    // MARK: – Termination

    func applicationWillTerminate(_ notification: Notification) {
        // Ensure the trackpad is always re-enabled on exit.
        // CGEventTapController.deinit already removes the tap, but being explicit is safer.
        if trackpadController.state == .disabled {
            trackpadController.enable()
            logger.info("Trackpad re-enabled on app exit")
        }
        HotKeyManager.shared.unregister()
    }

    // MARK: – Targeted actions (called from menu items)

    @objc func toggleTrackpad() {
        do {
            try trackpadController.toggle()
            logger.info("Toggled → \(self.trackpadController.state.displayTitle)")
        } catch TrackpadError.permissionRequired {
            showPermissionAlert()
        } catch TrackpadError.inputMonitoringRequired {
            showInputMonitoringAlert()
        } catch {
            showErrorAlert(message: error.localizedDescription)
        }
    }

    @objc func openSettings() {
        menuBarController?.showSettings()
    }

    @objc func grantAccessibility() {
        PermissionsManager.shared.openAccessibilitySettings()
    }

    @objc func grantInputMonitoring() {
        PermissionsManager.shared.openInputMonitoringSettings()
    }

    // MARK: – Sleep / wake

    @objc private func systemDidWake() {
        // After sleep+wake the OS may disable the event tap. If we're supposed to be
        // in the disabled state, reinstall it.
        guard trackpadController.state == .disabled else { return }
        logger.info("System woke — reinstalling event tap")
        trackpadController.enable()
        do {
            try trackpadController.disable()
        } catch {
            logger.error("Failed to reinstall tap after wake: \(error)")
        }
    }

    // MARK: – Alerts

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            Trackpad Toggle needs Accessibility access to install an event tap \
            that intercepts trackpad input.

            Click "Open Settings" and toggle the switch next to Trackpad Toggle. \
            You may need to quit and relaunch the app after granting permission.
            """
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            PermissionsManager.shared.openAccessibilitySettings()
        }
    }

    private func showInputMonitoringAlert() {
        let alert = NSAlert()
        alert.messageText = "Input Monitoring Permission Required"
        alert.informativeText = """
            Accessibility is granted but the event tap could not be installed. \
            This usually means Input Monitoring has not been granted.

            Open System Settings → Privacy & Security → Input Monitoring and \
            enable Trackpad Toggle. Then toggle the trackpad again.
            """
        alert.addButton(withTitle: "Open Input Monitoring Settings")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            PermissionsManager.shared.openInputMonitoringSettings()
        }
    }

    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Trackpad Toggle Error"
        alert.informativeText = message
        alert.alertStyle = .critical
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
