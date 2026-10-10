// LaunchAtLoginManager.swift
// Manages automatically starting Trackpad Toggle on user login.
// Uses macOS SMAppService.mainApp with a LaunchAgent plist fallback for maximum compatibility.

import Foundation
import ServiceManagement
import os.log

private let logger = Logger(subsystem: "com.powertools.trackpadtoggle", category: "LaunchAtLogin")

final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()
    private init() {}

    private let launchAgentIdentifier = "com.powertools.trackpadtoggle"

    private var launchAgentURL: URL {
        let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let agentsDir = libraryDir.appendingPathComponent("LaunchAgents", isDirectory: true)
        return agentsDir.appendingPathComponent("\(launchAgentIdentifier).plist")
    }

    /// Whether the app is currently configured to launch at login.
    var isEnabled: Bool {
        get {
            // Check SMAppService first if available
            if #available(macOS 13.0, *) {
                let status = SMAppService.mainApp.status
                if status == .enabled { return true }
            }
            // Check LaunchAgent fallback
            if FileManager.default.fileExists(atPath: launchAgentURL.path) {
                return true
            }
            // Check stored preference
            return Preferences.shared.launchAtLogin
        }
        set {
            setLaunchAtLogin(newValue)
        }
    }

    /// Updates launch at login configuration. Returns true if successful.
    @discardableResult
    func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        Preferences.shared.launchAtLogin = enabled

        var smAppSuccess = false
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                        logger.info("SMAppService registered successfully")
                    }
                    smAppSuccess = true
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                        logger.info("SMAppService unregistered successfully")
                    }
                    smAppSuccess = true
                }
            } catch {
                logger.warning("SMAppService register/unregister returned error: \(error.localizedDescription), using LaunchAgent fallback")
            }
        }

        // Maintain LaunchAgent plist as fallback / accompaniment
        if enabled {
            let plistSuccess = installLaunchAgentPlist()
            return smAppSuccess || plistSuccess
        } else {
            removeLaunchAgentPlist()
            return true
        }
    }

    // MARK: – LaunchAgent Plist Fallback

    private func installLaunchAgentPlist() -> Bool {
        guard let executablePath = Bundle.main.executablePath else {
            logger.error("Could not determine executable path for LaunchAgent")
            return false
        }

        let agentsDir = launchAgentURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Could not create LaunchAgents directory: \(error.localizedDescription)")
            return false
        }

        let plistContent: [String: Any] = [
            "Label": launchAgentIdentifier,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua"
        ]

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plistContent, format: .xml, options: 0)
            try data.write(to: launchAgentURL, options: .atomic)
            logger.info("LaunchAgent plist written to \(self.launchAgentURL.path)")
            return true
        } catch {
            logger.error("Failed to write LaunchAgent plist: \(error.localizedDescription)")
            return false
        }
    }

    private func removeLaunchAgentPlist() {
        if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            do {
                try FileManager.default.removeItem(at: launchAgentURL)
                logger.info("Removed LaunchAgent plist at \(self.launchAgentURL.path)")
            } catch {
                logger.error("Failed to remove LaunchAgent plist: \(error.localizedDescription)")
            }
        }
    }
}
