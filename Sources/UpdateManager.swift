// UpdateManager.swift
// Checks GitHub Releases API for new versions of Trackpad Toggle.
// Provides both automatic in-place DMG upgrade and browser release page access.

import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.powertools.trackpadtoggle", category: "UpdateManager")

final class UpdateManager {
    static let shared = UpdateManager()
    private init() {}

    private let repoURL = "https://api.github.com/repos/rajanraj2/trackpad-toggle/releases/latest"

    enum UpdateStatus: Equatable {
        case idle
        case checking
        case updateAvailable(version: String, releaseNotes: String?, downloadURL: URL, htmlURL: URL)
        case upToDate(version: String)
        case error(String)
    }

    private(set) var status: UpdateStatus = .idle {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onStatusChange?(self.status)
            }
        }
    }

    var onStatusChange: ((UpdateStatus) -> Void)?

    /// The running app's semantic version from Info.plist and Caskroom.
    var currentVersion: String {
        var baseVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        if isHomebrewManaged {
            let caskrooms = ["/opt/homebrew/Caskroom/trackpad-toggle", "/usr/local/Caskroom/trackpad-toggle"]
            for cr in caskrooms {
                if let entries = try? FileManager.default.contentsOfDirectory(atPath: cr) {
                    let versions = entries.filter { !$0.hasPrefix(".") }
                    if let latest = versions.sorted(by: { Self.isVersion($0, newerThan: $1) }).first {
                        if Self.isVersion(latest, newerThan: baseVersion) {
                            baseVersion = latest
                        }
                    }
                }
            }
        }
        return baseVersion
    }
    // MARK: – Homebrew Detection

    /// True if this application is managed by Homebrew Cask.
    var isHomebrewManaged: Bool {
        let paths = [
            "/opt/homebrew/Caskroom/trackpad-toggle",
            "/usr/local/Caskroom/trackpad-toggle"
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// Path to brew executable if installed.
    var brewExecutablePath: String? {
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: – Version Comparison (SemVer)

    /// Returns true if `remote` is strictly newer than `local` (e.g. "1.2.0" is newer than "1.1.0").
    static func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let cleanRemote = remote.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let cleanLocal = local.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))

        let remoteParts = cleanRemote.split(separator: ".").compactMap { Int($0) }
        let localParts = cleanLocal.split(separator: ".").compactMap { Int($0) }

        let count = max(remoteParts.count, localParts.count)
        for i in 0..<count {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }

    // MARK: – Check for Updates

    /// Checks the GitHub API for releases. Non-blocking and asynchronous.
    func checkForUpdates(manual: Bool = false) {
        status = .checking
        logger.info("Checking for updates via GitHub API… (current version: \(self.currentVersion))")

        guard let url = URL(string: repoURL) else {
            status = .error("Invalid update URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TrackpadToggle/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                logger.error("Update check failed: \(error.localizedDescription)")
                self.status = manual ? .error("Network error: \(error.localizedDescription)") : .idle
                return
            }

            guard let data = data else {
                self.status = manual ? .error("No data received from GitHub") : .idle
                return
            }

            do {
                let release = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
                let latestTag = release.tag_name
                let latestVersion = latestTag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))

                // Find the TrackpadToggle.dmg asset
                let dmgAsset = release.assets.first { $0.name.hasSuffix(".dmg") }
                guard let downloadURLString = dmgAsset?.browser_download_url,
                      let downloadURL = URL(string: downloadURLString),
                      let htmlURL = URL(string: release.html_url) else {
                    logger.warning("No .dmg asset found on latest release \(latestTag)")
                    self.status = manual ? .error("No DMG asset found on release \(latestTag)") : .idle
                    return
                }

                if Self.isVersion(latestVersion, newerThan: self.currentVersion) {
                    logger.info("Newer version available: \(latestVersion) > \(self.currentVersion)")
                    self.status = .updateAvailable(
                        version: latestVersion,
                        releaseNotes: release.body,
                        downloadURL: downloadURL,
                        htmlURL: htmlURL
                    )
                } else {
                    logger.info("App is up to date (\(self.currentVersion))")
                    self.status = .upToDate(version: self.currentVersion)
                }
            } catch {
                logger.error("Failed to parse release JSON: \(error.localizedDescription)")
                self.status = manual ? .error("Failed to parse GitHub release") : .idle
            }
        }.resume()
    }

    // MARK: – In-Place Automatic Upgrade (Unified Single Source of Truth)

    /// Upgrades the application to the new version by downloading and mounting the latest
    /// official release DMG, cleanly replacing the running application bundle, stripping
    /// Gatekeeper quarantine attributes, synchronizing Homebrew Caskroom metadata, and relaunching.
    func downloadAndInstallUpdate(
        from downloadURL: URL,
        targetVersion: String? = nil,
        progressHandler: @escaping (String) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        performDirectDMGUpgrade(from: downloadURL, targetVersion: targetVersion, progressHandler: progressHandler, completion: completion)
    }

    private func performDirectDMGUpgrade(
        from downloadURL: URL,
        targetVersion: String?,
        progressHandler: @escaping (String) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        progressHandler("Downloading latest release…")
        logger.info("Starting download of \(downloadURL.absoluteString)")

        let task = URLSession.shared.downloadTask(with: downloadURL) { [weak self] tempLocation, response, error in
            guard let self = self else { return }

            if let error = error {
                completion(.failure(error))
                return
            }

            guard let tempLocation = tempLocation else {
                completion(.failure(UpdateError.downloadFailed("No file saved")))
                return
            }

            progressHandler("Mounting update disk image…")
            let tempDMG = "/tmp/TrackpadToggle_update_\(ProcessInfo.processInfo.globallyUniqueString).dmg"
            let mountDir = "/tmp/TrackpadToggle_mount_\(ProcessInfo.processInfo.globallyUniqueString)"

            do {
                try? FileManager.default.removeItem(atPath: tempDMG)
                try FileManager.default.moveItem(at: tempLocation, to: URL(fileURLWithPath: tempDMG))

                try FileManager.default.createDirectory(atPath: mountDir, withIntermediateDirectories: true)

                // 1. Mount DMG
                let attachProc = Process()
                attachProc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                attachProc.arguments = ["attach", "-nobrowse", "-readonly", "-mountpoint", mountDir, tempDMG]
                try attachProc.run()
                attachProc.waitUntilExit()

                guard attachProc.terminationStatus == 0 else {
                    throw UpdateError.installFailed("Failed to mount downloaded disk image")
                }

                // 2. Find new .app inside mount
                let sourceApp = "\(mountDir)/TrackpadToggle.app"
                guard FileManager.default.fileExists(atPath: sourceApp) else {
                    throw UpdateError.installFailed("TrackpadToggle.app not found inside disk image")
                }

                // 3. Determine target app location
                let currentBundle = Bundle.main.bundlePath
                let targetApp = currentBundle.hasSuffix(".app") ? currentBundle : "/Applications/TrackpadToggle.app"
                progressHandler("Installing update to \(targetApp)…")

                // Move existing bundle out of the way for atomic replacement
                let backupApp = "/tmp/TrackpadToggle_backup_\(ProcessInfo.processInfo.globallyUniqueString).app"
                try? FileManager.default.removeItem(atPath: backupApp)
                if FileManager.default.fileExists(atPath: targetApp) {
                    try? FileManager.default.moveItem(atPath: targetApp, toPath: backupApp)
                }

                // Copy new bundle into place
                let cpProc = Process()
                cpProc.executableURL = URL(fileURLWithPath: "/bin/cp")
                cpProc.arguments = ["-R", sourceApp, targetApp]
                try cpProc.run()
                cpProc.waitUntilExit()

                // Strip quarantine attribute on the updated app so Gatekeeper doesn't block it
                let xattrProc = Process()
                xattrProc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                xattrProc.arguments = ["-d", "-r", "com.apple.quarantine", targetApp]
                try? xattrProc.run()
                xattrProc.waitUntilExit()

                // 4. Detach DMG and cleanup
                let detachProc = Process()
                detachProc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                detachProc.arguments = ["detach", mountDir, "-force"]
                try? detachProc.run()
                detachProc.waitUntilExit()

                try? FileManager.default.removeItem(atPath: tempDMG)
                try? FileManager.default.removeItem(atPath: mountDir)
                try? FileManager.default.removeItem(atPath: backupApp)

                // 5. Synchronize Homebrew Caskroom metadata so `brew list --cask --versions` matches!
                if let version = targetVersion {
                    self.syncHomebrewCaskroom(to: version, sourceApp: targetApp)
                }

                progressHandler("Relaunching Trackpad Toggle…")
                logger.info("Update installed successfully. Relaunching \(targetApp)…")

                self.relaunchAndTerminate(targetApp: targetApp)
                completion(.success(()))
            } catch {
                logger.error("Update installation failed: \(error.localizedDescription)")
                // Attempt cleanup
                let detachProc = Process()
                detachProc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                detachProc.arguments = ["detach", mountDir, "-force"]
                try? detachProc.run()

                completion(.failure(error))
            }
        }
        task.resume()
    }

    // MARK: – Caskroom Synchronization

    /// Keeps Homebrew Caskroom directory in sync when the app is updated directly via DMG,
    /// ensuring `brew list --cask --versions` and `/Applications` always report the exact same version.
    func syncHomebrewCaskroom(to newVersion: String, sourceApp: String) {
        let caskrooms = [
            "/opt/homebrew/Caskroom/trackpad-toggle",
            "/usr/local/Caskroom/trackpad-toggle"
        ]
        for caskroom in caskrooms {
            guard FileManager.default.fileExists(atPath: caskroom) else { continue }
            let targetVerDir = "\(caskroom)/\(newVersion)"
            do {
                // Remove any older version folders in Caskroom
                let entries = try FileManager.default.contentsOfDirectory(atPath: caskroom)
                for entry in entries where !entry.hasPrefix(".") && entry != newVersion {
                    let oldPath = "\(caskroom)/\(entry)"
                    logger.info("Removing stale Caskroom version folder: \(oldPath)")
                    try? FileManager.default.removeItem(atPath: oldPath)
                }
                // Create new version directory and copy app bundle
                try FileManager.default.createDirectory(atPath: targetVerDir, withIntermediateDirectories: true)
                let destApp = "\(targetVerDir)/TrackpadToggle.app"
                try? FileManager.default.removeItem(atPath: destApp)
                let cpProc = Process()
                cpProc.executableURL = URL(fileURLWithPath: "/bin/cp")
                cpProc.arguments = ["-R", sourceApp, destApp]
                try cpProc.run()
                cpProc.waitUntilExit()
                logger.info("Synchronized Caskroom to \(targetVerDir)")
            } catch {
                logger.warning("Failed to sync Caskroom: \(error.localizedDescription)")
            }
        }
    }

    // MARK: – Clean Relaunch & Single-Instance Termination

    private func relaunchAndTerminate(targetApp: String) {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "com.powertools.trackpadtoggle"

        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) where app.processIdentifier != currentPID {
            app.terminate()
        }

        // Wait for current process to completely exit before launching new binary, preventing macOS from reactivating the old PID
        let relaunchScript = """
        count=0
        while kill -0 \(currentPID) 2>/dev/null; do
            sleep 0.1
            count=$((count + 1))
            if [ $count -gt 25 ]; then
                kill -9 \(currentPID) 2>/dev/null || true
                break
            fi
        done
        open -n "\(targetApp)"
        """

        let shProc = Process()
        shProc.executableURL = URL(fileURLWithPath: "/bin/sh")
        shProc.arguments = ["-c", relaunchScript]
        try? shProc.run()

        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }

    enum UpdateError: LocalizedError {
        case downloadFailed(String)
        case installFailed(String)

        var errorDescription: String? {
            switch self {
            case .downloadFailed(let msg): return "Download error: \(msg)"
            case .installFailed(let msg): return "Install error: \(msg)"
            }
        }
    }
}

// MARK: – GitHub API Response Models

private struct GitHubReleasePayload: Decodable {
    let tag_name: String
    let name: String?
    let body: String?
    let html_url: String
    let assets: [GitHubAssetPayload]
}

private struct GitHubAssetPayload: Decodable {
    let name: String
    let browser_download_url: String
}
