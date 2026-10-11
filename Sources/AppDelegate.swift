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

        // 0. Enforce single instance: terminate any older running instances
        enforceSingleInstance()

        // 1. Build the trackpad controller.
        trackpadController = CGEventTapController()

        // 2. Wire the menu bar.
        let mbc = MenuBarController(controller: trackpadController)
        menuBarController = mbc

        // 3. Register both Carbon hotkeys and wire the event-tap full-lock shortcut.
        HotKeyManager.shared.onTrackpadHotKey = { [weak self] in
            self?.toggleTrackpadOnly()
        }
        HotKeyManager.shared.onFullLockHotKey = { [weak self] in
            self?.toggleFullLock()
        }
        trackpadController.onFullLockShortcut = { [weak self] in
            self?.toggleFullLock()
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

        // 6. Check for updates in background (2 seconds after launch)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            UpdateManager.shared.checkForUpdates(manual: false)
        }

        // 7. If menu bar icon is hidden, open Settings window so user has interface
        if !Preferences.shared.showMenuBarIcon {
            openSettings()
        }

        logger.info("Startup complete. Trackpad shortcut: \(Preferences.shared.hotKeyDescription); Full Lock: \(Preferences.shared.keyboardUnlockShortcutDescription)")
    }

    // MARK: – Application Reopen (From Applications, Launchpad, Spotlight)

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }
    // MARK: – Termination

    func applicationWillTerminate(_ notification: Notification) {
        // Ensure trackpad and cursor are always re-enabled and reconnected on exit.
        CGAssociateMouseAndMouseCursorPosition(1)
        if trackpadController.state == .disabled {
            trackpadController.enable()
            logger.info("Trackpad re-enabled on app exit")
        }
        HotKeyManager.shared.unregister()
    }

    // MARK: – Targeted actions (called from menu items)

    @objc func toggleTrackpadOnly() {
        do {
            try trackpadController.toggleTrackpadOnly()
            logger.info("Toggled trackpad-only → \(self.trackpadController.state.displayTitle)")
        } catch TrackpadError.permissionRequired {
            showPermissionAlert()
        } catch TrackpadError.inputMonitoringRequired {
            showInputMonitoringAlert()
        } catch {
            showErrorAlert(message: error.localizedDescription)
        }
    }

    @objc func toggleFullLock() {
        do {
            try trackpadController.toggleFullLock()
            logger.info("Toggled full-lock → \(self.trackpadController.state.displayTitle)")
        } catch TrackpadError.permissionRequired {
            showPermissionAlert()
        } catch TrackpadError.inputMonitoringRequired {
            showInputMonitoringAlert()
        } catch {
            showErrorAlert(message: error.localizedDescription)
        }
    }

    @objc func toggleTrackpad() {
        toggleTrackpadOnly()
    }

    @objc func openSettings() {
        menuBarController?.showSettings()
    }

    @objc func changeShortcut() {
        menuBarController?.showSettings(focusShortcut: true)
    }

    @objc func toggleLaunchAtLogin() {
        let current = LaunchAtLoginManager.shared.isEnabled
        _ = LaunchAtLoginManager.shared.setLaunchAtLogin(!current)
        menuBarController?.rebuildMenu()
    }

    @objc func toggleBlockCursorAndGestures() {
        let current = Preferences.shared.blockCursorAndGestures
        Preferences.shared.blockCursorAndGestures = !current
        trackpadController.updateSuppressionMode()
        logger.info("Toggled blockCursorAndGestures to: \(!current)")
        menuBarController?.rebuildMenu()
    }
    @objc func grantAccessibility() {
        PermissionsManager.shared.openAccessibilitySettings()
    }

    @objc func grantInputMonitoring() {
        PermissionsManager.shared.openInputMonitoringSettings()
    }

    // MARK: – In-App Updates

    @objc func checkForUpdatesManual() {
        UpdateManager.shared.checkForUpdates(manual: true)
        menuBarController?.rebuildMenu()
    }

    @objc func promptUpdate() {
        guard case .updateAvailable(let newVer, let notes, let downloadURL, let htmlURL) = UpdateManager.shared.status else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Trackpad Toggle v\(newVer) is Available!"
        if let icon = loadAppIcon() { alert.icon = icon }
        var info = "You are currently running v\(UpdateManager.shared.currentVersion).\n\n"
        if let notes = notes, !notes.isEmpty {
            info += "Release Highlights:\n\(notes.prefix(300))\n\n"
        }
        info += "Would you like to download and install this update automatically?"
        alert.informativeText = info
        alert.addButton(withTitle: "Download & Install Now")
        alert.addButton(withTitle: "View on GitHub")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            performAutomaticUpgrade(from: downloadURL, targetVersion: newVer)
        } else if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(htmlURL)
        }
    }

    private func performAutomaticUpgrade(from url: URL, targetVersion: String) {
        let progressAlert = NSAlert()
        if let icon = loadAppIcon() { progressAlert.icon = icon }
        progressAlert.informativeText = "Downloading latest release and installing to /Applications…"
        progressAlert.addButton(withTitle: "Cancel")
        progressAlert.alertStyle = .informational

        UpdateManager.shared.downloadAndInstallUpdate(
            from: url,
            targetVersion: targetVersion,
            progressHandler: { msg in
                DispatchQueue.main.async {
                    progressAlert.informativeText = msg
                }
            },
            completion: { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        break
                    case .failure(let error):
                        let errorAlert = NSAlert()
                        errorAlert.messageText = "Update Failed"
                        errorAlert.informativeText = "Could not install update: \(error.localizedDescription)\n\nAlternatively, install via Homebrew:\nbrew upgrade --cask trackpad-toggle"
                        errorAlert.alertStyle = .critical
                        errorAlert.addButton(withTitle: "OK")
                        errorAlert.runModal()
                    }
                }
            }
        )
    }

    // MARK: – Single Instance Enforcement

    /// Ensures that only a single instance of Trackpad Toggle runs on the system.
    /// If an older version or another instance is running, terminates it immediately.
    private func enforceSingleInstance() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "com.powertools.trackpadtoggle"
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for app in instances where app.processIdentifier != currentPID {
            logger.info("Found other running instance PID \(app.processIdentifier). Terminating…")
            app.terminate()
        }
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
        if let icon = loadAppIcon() { alert.icon = icon }
        alert.informativeText = """
            Trackpad Toggle needs Accessibility access to intercept trackpad input.

            • If Trackpad Toggle is already enabled in System Settings:
              macOS has cached an older binary signature. Click "Reset Permission Cache" below to fix this automatically.

            • Alternatively in System Settings:
              Select Trackpad Toggle, click the minus button (-) to remove it, then re-add it.
            """
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Reset Permission Cache (Fix Stale Hash)")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            PermissionsManager.shared.openAccessibilitySettings()
        } else if resp == .alertSecondButtonReturn {
            PermissionsManager.shared.resetPermissions()
            PermissionsManager.shared.openAccessibilitySettings()
        }
    }

    private func showInputMonitoringAlert() {
        let alert = NSAlert()
        if let icon = loadAppIcon() { alert.icon = icon }
        alert.informativeText = """
            Input Monitoring permission is required to suppress trackpad events.

            • If Trackpad Toggle is already enabled:
              Click "Reset Permission Cache" below, or in System Settings, select Trackpad Toggle, click the minus button (-) to remove it, and re-add it.
            """
        alert.addButton(withTitle: "Open Input Monitoring Settings")
        alert.addButton(withTitle: "Reset Permission Cache (Fix Stale Hash)")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            PermissionsManager.shared.openInputMonitoringSettings()
        } else if resp == .alertSecondButtonReturn {
            PermissionsManager.shared.resetPermissions()
            PermissionsManager.shared.openInputMonitoringSettings()
        }
    }

    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        if let icon = loadAppIcon() { alert.icon = icon }
        alert.informativeText = message
        alert.alertStyle = .critical
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func loadAppIcon() -> NSImage? {
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        return NSImage(named: NSImage.applicationIconName)
    }
}
