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
}
