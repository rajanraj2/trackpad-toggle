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

        // 6. Check for updates in background (2 seconds after launch)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            UpdateManager.shared.checkForUpdates(manual: false)
        }

        logger.info("Startup complete. Shortcut: \(Preferences.shared.hotKeyDescription)")
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
        var token: ((UpdateManager.UpdateStatus) -> Void)?
        token = { [weak self] status in
            switch status {
            case .updateAvailable:
                self?.promptUpdate()
            case .upToDate(let ver):
                let alert = NSAlert()
                alert.messageText = "Trackpad Toggle is Up to Date"
                alert.informativeText = "You are currently running version \(ver), which is the latest available release."
                alert.alertStyle = .informational
                alert.runModal()
            case .error(let msg):
                let alert = NSAlert()
                alert.messageText = "Check for Updates Failed"
                alert.informativeText = msg
                alert.alertStyle = .warning
                alert.runModal()
            default:
                break
            }
        }
        UpdateManager.shared.onStatusChange = { status in
            token?(status)
            (NSApp.delegate as? AppDelegate)?.menuBarController?.rebuildMenu()
        }
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
            performAutomaticUpgrade(from: downloadURL)
        } else if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(htmlURL)
        }
    }

    private func performAutomaticUpgrade(from url: URL) {
        let progressAlert = NSAlert()
        if let icon = loadAppIcon() { progressAlert.icon = icon }
        progressAlert.informativeText = "Downloading latest release and installing to /Applications…"
        progressAlert.addButton(withTitle: "Cancel")
        progressAlert.alertStyle = .informational

        UpdateManager.shared.downloadAndInstallUpdate(from: url, progressHandler: { msg in
            DispatchQueue.main.async {
                progressAlert.informativeText = msg
            }
        }, completion: { result in
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
        })
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
