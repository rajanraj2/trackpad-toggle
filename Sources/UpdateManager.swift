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

    /// The running app's semantic version from Info.plist (e.g. "1.1.0").
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
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

    // MARK: – In-Place Automatic Upgrade

    /// Downloads the latest DMG, replaces the app bundle in /Applications, strips quarantine, and relaunches.
    func downloadAndInstallUpdate(
        from downloadURL: URL,
        progressHandler: @escaping (String) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        progressHandler("Downloading latest release…")
        logger.info("Starting download of \(downloadURL.absoluteString)")

        let task = URLSession.shared.downloadTask(with: downloadURL) { [weak self] tempLocation, response, error in
            guard self != nil else { return }

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

                // 3. Determine target app location (/Applications/TrackpadToggle.app or Bundle path)
                var targetApp = "/Applications/TrackpadToggle.app"
                let currentBundle = Bundle.main.bundlePath
                if currentBundle.hasPrefix("/Applications") {
                    targetApp = currentBundle
                } else if currentBundle.contains("/Applications") {
                    targetApp = currentBundle
                }

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

                progressHandler("Relaunching Trackpad Toggle…")
                logger.info("Update installed successfully. Relaunching \(targetApp)…")

                // Spawn background process to reopen the new version after current process quits
                let relaunchScript = "sleep 0.8 && open \"\(targetApp)\""
                let shProc = Process()
                shProc.executableURL = URL(fileURLWithPath: "/bin/sh")
                shProc.arguments = ["-c", relaunchScript]
                try? shProc.run()

                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
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
