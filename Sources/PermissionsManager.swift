// PermissionsManager.swift
// Checks and opens the macOS Accessibility and Input Monitoring TCC entries.
// Both are required for CGEventTap in kCGEventTapOptionDefault (active/suppression) mode.

import AppKit
import ApplicationServices

final class PermissionsManager {
    static let shared = PermissionsManager()
    private init() {}

    // MARK: – Checks

    /// True when the Accessibility permission is granted for this process.
    var hasAccessibility: Bool {
        // kAXTrustedCheckOptionPrompt is Unmanaged<CFString>, not Hashable.
        // Bridge via NSDictionary so Swift accepts the literal.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    /// True when both required permissions are granted.
    /// Input Monitoring cannot be checked programmatically via a public API that returns
    /// a Bool without attempting to create a tap; we use the Accessibility check as the
    /// gate and rely on tap-creation failure as the runtime signal for missing IM access.
    var allGranted: Bool { hasAccessibility }

    // MARK: – Prompts

    /// Triggers the system Accessibility prompt (shows the grant dialog).
    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    /// Opens System Settings → Privacy & Security → Accessibility.
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Opens System Settings → Privacy & Security → Input Monitoring.
    func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    // MARK: – Reset Stale TCC Cache

    /// Resets stale Accessibility and Input Monitoring approval records using tccutil.
    /// Essential when an app binary is upgraded or rebuilt and macOS cached a previous signature hash.
    @discardableResult
    func resetPermissions() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.powertools.trackpadtoggle"

        let p1 = Process()
        p1.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p1.arguments = ["reset", "Accessibility", bundleID]
        try? p1.run()
        p1.waitUntilExit()

        let p2 = Process()
        p2.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p2.arguments = ["reset", "ListenEvent", bundleID]
        try? p2.run()
        p2.waitUntilExit()

        return true
    }
}
