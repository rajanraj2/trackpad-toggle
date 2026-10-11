// SettingsWindowController.swift
// Native macOS Settings window featuring:
//   • Configurable Global Shortcut (recording, presets, conflict detection, Esc to cancel)
//   • Startup / Launch at Login option (SMAppService + LaunchAgent fallback)
//   • Permission status and direct System Settings deep-links
//   • Diagnostics, status overview, and recovery instructions

import AppKit
import SwiftUI
import Carbon
import ServiceManagement
import os.log
private let logger = Logger(subsystem: "com.powertools.trackpadtoggle", category: "Settings")

// MARK: – Settings Window Controller

final class SettingsWindowController: NSWindowController {

    let viewModel: SettingsViewModel

    convenience init() {
        let vm = SettingsViewModel()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Trackpad Toggle — Settings"
        window.isReleasedWhenClosed = false
        window.center()

        let contentView = SettingsView(vm: vm)
        window.contentView = NSHostingView(rootView: contentView)

        self.init(window: window, viewModel: vm)
    }

    init(window: NSWindow, viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Activates recording mode directly when user selects "Change Shortcut…" from the menu bar.
    func startRecordingShortcut() {
        viewModel.startRecording()
    }
}

// MARK: – Main Settings View

private struct SettingsView: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        Form {
            // ── App Brand Header ──────────────────────────────────────────────
            HStack(spacing: 16) {
                if let iconImage = loadAppIcon() {
                    Image(nsImage: iconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                } else {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.accentColor)
                        .frame(width: 56, height: 56)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Trackpad Toggle")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("macOS Built-in Trackpad Disabler & Shortcut Controller")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)

            // ── Trackpad Control & Status ─────────────────────────────────────
            Section("Trackpad Control") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Trackpad: \(vm.stateDescription)")
                                .fontWeight(.medium)
                            Text("Shortcut: \(vm.shortcutDescription)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()

                        Button(action: { vm.toggleTrackpad() }) {
                            HStack(spacing: 6) {
                                Image(systemName: vm.isTrackpadDisabled ? "hand.point.up.left.fill" : "hand.raised.slash.fill")
                                Text(vm.isTrackpadDisabled ? "Enable Trackpad" : "Disable Trackpad")
                            }
                            .padding(.horizontal, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(vm.isTrackpadDisabled ? .green : .red)
                    }

                    LabeledContent("Launch on Startup") {
                        Text(vm.launchAtLogin ? "Enabled" : "Disabled")
                            .foregroundColor(vm.launchAtLogin ? .green : .secondary)
                    }
                }
            }

            // ── Shortcut Configuration ────────────────────────────────────────
            Section("Keyboard Shortcut Configuration") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Toggle Shortcut:")
                            .fontWeight(.medium)
                        Spacer()

                        if vm.isRecordingToggle {
                            // Active recorder field
                            ShortcutRecorderField(
                                displayText: vm.toggleRecorderDisplayText,
                                isRecording: vm.isRecordingToggle,
                                onCommit: { code, mods in
                                    vm.commitShortcut(code: code, mods: mods)
                                },
                                onCancel: {
                                    vm.cancelRecording()
                                }
                            )
                            .frame(width: 180, height: 26)

                            Button("Cancel") {
                                vm.cancelRecording()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            // Display badge and Record button
                            Text(vm.shortcutDescription)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.bold)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.12))
                                .cornerRadius(6)

                            Button("Change Shortcut…") {
                                vm.startRecording()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    if vm.isRecordingToggle {
                        HStack(spacing: 4) {
                            Image(systemName: "record.circle.fill")
                                .foregroundColor(.red)
                            Text("Listening for key combination… Press any shortcut with modifiers (⌘, ⌥, ⌃, ⇧). Press Esc to cancel.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 2)
                    }

                    Divider()

                    HStack {
                        Text("Keyboard Unlock Shortcut:")
                            .fontWeight(.medium)
                        Spacer()

                        if vm.isRecordingKeyboardUnlock {
                            ShortcutRecorderField(
                                displayText: vm.keyboardUnlockRecorderDisplayText,
                                isRecording: vm.isRecordingKeyboardUnlock,
                                onCommit: { code, mods in
                                    vm.commitKeyboardUnlockShortcut(code: code, mods: mods)
                                },
                                onCancel: {
                                    vm.cancelRecording()
                                }
                            )
                            .frame(width: 180, height: 26)

                            Button("Cancel") {
                                vm.cancelRecording()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Text(vm.keyboardUnlockShortcutDescription)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.bold)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.12))
                                .cornerRadius(6)

                            Button("Change Unlock Shortcut…") {
                                vm.startRecordingKeyboardUnlock()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    if vm.isRecordingKeyboardUnlock {
                        HStack(spacing: 4) {
                            Image(systemName: "record.circle.fill")
                                .foregroundColor(.red)
                            Text("Choose the only keyboard shortcut that exits cleaning mode. Press Esc to cancel.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 2)
                    } else {
                        Text("While cleaning mode is active, all keyboard input is blocked. This shortcut is consumed to restore the keyboard and trackpad.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Status feedback message (success / conflict / warning)
                    if let message = vm.shortcutMessage {
                        HStack(spacing: 6) {
                            Image(systemName: vm.shortcutMessageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundColor(vm.shortcutMessageIsError ? .orange : .green)
                            Text(message)
                                .font(.caption)
                                .foregroundColor(vm.shortcutMessageIsError ? .primary : .secondary)
                        }
                        .padding(.vertical, 2)
                    }

                    // Presets
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Quick Presets:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            ForEach(Preferences.presets) { preset in
                                Button(action: { vm.applyPreset(preset) }) {
                                    Text("\(preset.display) (\(preset.title))")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .tint(vm.shortcutDescription == preset.display ? .accentColor : nil)
                            }
                        }
                    }
                    .padding(.top, 4)

                    Text("The start shortcut is registered globally with Carbon. During cleaning mode, the event tap blocks every keyboard event except the configurable unlock shortcut above.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            // ── Input Suppression Mode ─────────────────────────────────────────
            Section("Input Suppression Mode") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Block Cursor Movement & Gestures", isOn: $vm.blockCursorAndGestures)
                        .toggleStyle(.switch)

                    Text("Keyboard input is always blocked during cleaning mode. This setting controls whether cursor movement and multi-touch gestures are also completely blocked.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if vm.blockCursorAndGestures {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill").foregroundColor(.accentColor)
                            Text("Full Lockdown: Keyboard, cursor movement, gestures, clicks, and scrolling are blocked.")
                                .font(.caption2)
                                .foregroundColor(.accentColor)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.open.fill").foregroundColor(.secondary)
                            Text("Partial Mode: Keyboard, clicks, and scrolling are blocked, but cursor movement is allowed.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // ── Startup & Login ───────────────────────────────────────────────
            Section("Startup Settings") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Start automatically at login", isOn: $vm.launchAtLogin)
                        .toggleStyle(.switch)

                    Text("When enabled, Trackpad Toggle starts automatically in the menu bar when you log into macOS. You can toggle the trackpad at any time.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if vm.launchAtLogin {
                        Text("✓ Registered in macOS Login Items (runs in background as menu bar accessory).")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }

            // ── Menu Bar Appearance ───────────────────────────────────────────
            Section("Menu Bar Appearance") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Show icon in menu bar", isOn: $vm.showMenuBarIcon)
                        .toggleStyle(.switch)
                    Text("When disabled, Trackpad Toggle runs silently in the background without taking up space in your menu bar.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !vm.showMenuBarIcon {
                        Text("💡 Tip: When the menu bar icon is hidden, simply open Trackpad Toggle from Spotlight (⌘Space), Launchpad, or Applications to access Settings. Your global shortcut works at all times.")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                }
            }

            // ── Permissions ───────────────────────────────────────────────────
            Section("macOS Permissions") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: vm.axGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(vm.axGranted ? .green : .red)
                        Text("Accessibility Permission")
                        Spacer()
                        if !vm.axGranted {
                            Button("Grant Access…") {
                                PermissionsManager.shared.openAccessibilitySettings()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.secondary)
                        Text("Input Monitoring Permission")
                        Spacer()
                        Button("Open Settings…") {
                            PermissionsManager.shared.openInputMonitoringSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("Accessibility allows creating the event tap; Input Monitoring allows dropping trackpad and keyboard events. Both are required for cleaning mode.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider().padding(.vertical, 2)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fix Permission Loop")
                                .font(.caption).bold()
                            Text("If toggled ON in System Settings but still prompts, macOS cached a stale binary signature hash.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Reset Permission Cache") {
                            vm.resetPermissionCache()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            // ── Diagnostics ───────────────────────────────────────────────────
            Section("Diagnostics & Troubleshooting") {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("macOS Version", value: ProcessInfo.processInfo.operatingSystemVersionString)
                    LabeledContent("Control Engine", value: "CGEventTap (kCGHIDEventTap)")
                    LabeledContent("Hotkey Engine", value: "Carbon RegisterEventHotKey")

                    HStack {
                        Button("Run Full Diagnostics") { vm.runDiagnostics() }
                        Spacer()
                        Button("Reset to Defaults", role: .destructive) { vm.resetToDefaults() }
                    }

                    if let diag = vm.diagnosticResult {
                        Text(diag)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                            .textSelection(.enabled)
                    }
                }
            }
            // ── Software Updates ──────────────────────────────────────────────
            Section("Software Updates") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Installed Version: v\(vm.currentVersion)")
                                .fontWeight(.medium)
                            if case .updateAvailable(let newVer, _, _, _) = vm.updateStatus {
                                Text("⭐️ Version v\(newVer) is available!")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } else {
                                Text("✓ You are running the latest version.")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        Spacer()

                        if case .updateAvailable = vm.updateStatus {
                            Button("Install & Update Now") {
                                vm.installUpdate()
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("Check for Updates") {
                                vm.checkForUpdates()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            // ── Safe Recovery ─────────────────────────────────────────────────
            Section("Emergency Recovery") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("If cleaning mode is active and you need to restore control:")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("1. Press the keyboard unlock shortcut (\(vm.keyboardUnlockShortcutDescription)) to immediately restore the keyboard and trackpad.")
                    Text("2. If the app is open, click Quit Trackpad Toggle with an external mouse.")
                    Text("3. Restart your Mac — all input is unconditionally restored at reboot.")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            // ── Quit Application ──────────────────────────────────────────────
            Section {
                Button("Quit Trackpad Toggle", role: .destructive) {
                    NSApp.terminate(nil)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 480, minHeight: 600)
        .onAppear { vm.refresh() }
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

// MARK: – NSViewRepresentable Shortcut Field

private struct ShortcutRecorderField: NSViewRepresentable {
    var displayText: String
    var isRecording: Bool
    var onCommit: (UInt32, UInt32) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> RecorderTextField {
        let field = RecorderTextField()
        field.onCommit = onCommit
        field.onCancel = onCancel
        return field
    }

    func updateNSView(_ nsView: RecorderTextField, context: Context) {
        nsView.isInRecordingMode = isRecording
        nsView.updateDisplay(displayText)
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

/// Custom NSTextField that intercepts key events during shortcut recording.
final class RecorderTextField: NSTextField {
    var onCommit: ((UInt32, UInt32) -> Void)?
    var onCancel: (() -> Void)?

    var isInRecordingMode = false {
        didSet { refreshDisplay() }
    }

    private var savedDisplayText = Preferences.shared.hotKeyDescription

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBezeled = true
        isEditable = false
        isSelectable = false
        alignment = .center
        wantsLayer = true
        refreshDisplay()
    }
    required init?(coder: NSCoder) { fatalError() }

    func updateDisplay(_ text: String) {
        savedDisplayText = text
        if !isInRecordingMode { stringValue = text }
    }

    private func refreshDisplay() {
        stringValue = isInRecordingMode ? "Press key combo…" : savedDisplayText
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isInRecordingMode else {
            super.keyDown(with: event)
            return
        }

        // Escape (0x35 = 53): cancel recording
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        let carbonMods = cocoaModsToCarbonMods(event.modifierFlags)
        let carbonCode = UInt32(event.keyCode)

        // Must have at least one modifier key, OR be a function key (keyCode >= 0x60)
        guard carbonMods != 0 || event.keyCode >= 0x60 else {
            // Give visual feedback in field
            stringValue = "Include ⌘, ⌥, ⌃, or ⇧!"
            return
        }

        onCommit?(carbonCode, carbonMods)
    }

    private func cocoaModsToCarbonMods(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        return mods
    }
}

// MARK: – Settings View Model

@MainActor
final class SettingsViewModel: ObservableObject {

    private enum RecordingTarget {
        case toggle
        case keyboardUnlock
    }

    @Published var axGranted = false
    @Published var stateDescription = ""
    @Published var shortcutDescription = Preferences.shared.hotKeyDescription
    @Published var keyboardUnlockShortcutDescription = Preferences.shared.keyboardUnlockShortcutDescription
    @Published private var recordingTarget: RecordingTarget?
    @Published var shortcutMessage: String?
    @Published var shortcutMessageIsError = false
    @Published var diagnosticResult: String?

    @Published var launchAtLogin: Bool = LaunchAtLoginManager.shared.isEnabled {
        didSet {
            if launchAtLogin != oldValue {
                let success = LaunchAtLoginManager.shared.setLaunchAtLogin(launchAtLogin)
                if !success {
                    logger.warning("Could not persist launch at login change")
                }
                (NSApp.delegate as? AppDelegate)?.menuBarController?.rebuildMenu()
            }
        }
    }

    @Published var blockCursorAndGestures: Bool = Preferences.shared.blockCursorAndGestures {
        didSet {
            Preferences.shared.blockCursorAndGestures = blockCursorAndGestures
            (NSApp.delegate as? AppDelegate)?.trackpadController.updateSuppressionMode()
            (NSApp.delegate as? AppDelegate)?.menuBarController?.rebuildMenu()
        }
    }

    @Published var showMenuBarIcon: Bool = Preferences.shared.showMenuBarIcon {
        didSet {
            Preferences.shared.showMenuBarIcon = showMenuBarIcon
            (NSApp.delegate as? AppDelegate)?.menuBarController?.updateVisibility()
        }
    }

    var isRecordingToggle: Bool {
        recordingTarget == .toggle
    }

    var isRecordingKeyboardUnlock: Bool {
        recordingTarget == .keyboardUnlock
    }

    var toggleRecorderDisplayText: String {
        isRecordingToggle ? "Press keys…" : shortcutDescription
    }

    var keyboardUnlockRecorderDisplayText: String {
        isRecordingKeyboardUnlock ? "Press keys…" : keyboardUnlockShortcutDescription
    }
    var isTrackpadDisabled: Bool {
        (NSApp.delegate as? AppDelegate)?.trackpadController.state == .disabled
    }

    var currentVersion: String {
        UpdateManager.shared.currentVersion
    }

    var updateStatus: UpdateManager.UpdateStatus {
        UpdateManager.shared.status
    }

    func toggleTrackpad() {
        (NSApp.delegate as? AppDelegate)?.toggleTrackpad()
        refresh()
    }

    func checkForUpdates() {
        (NSApp.delegate as? AppDelegate)?.checkForUpdatesManual()
        refresh()
    }

    func installUpdate() {
        (NSApp.delegate as? AppDelegate)?.promptUpdate()
    }

    func refresh() {
        shortcutDescription = Preferences.shared.hotKeyDescription
        keyboardUnlockShortcutDescription = Preferences.shared.keyboardUnlockShortcutDescription
        launchAtLogin = LaunchAtLoginManager.shared.isEnabled
        blockCursorAndGestures = Preferences.shared.blockCursorAndGestures
        showMenuBarIcon = Preferences.shared.showMenuBarIcon
        if let ctrl = (NSApp.delegate as? AppDelegate)?.trackpadController {
            stateDescription = ctrl.state.displayTitle
        }
    }
    func startRecording() {
        recordingTarget = .toggle
        shortcutMessage = nil
    }

    func startRecordingKeyboardUnlock() {
        recordingTarget = .keyboardUnlock
        shortcutMessage = nil
    }

    func cancelRecording() {
        recordingTarget = nil
        shortcutMessage = nil
    }

    func commitShortcut(code: UInt32, mods: UInt32) {
        Preferences.shared.hotKeyCode = code
        Preferences.shared.hotKeyModifiers = mods
        shortcutDescription = Preferences.shared.hotKeyDescription
        recordingTarget = nil

        let result = HotKeyManager.shared.register()
        switch result {
        case .success:
            shortcutMessage = "✓ Shortcut updated to \(shortcutDescription)"
            shortcutMessageIsError = false
        case .conflict(let msg):
            shortcutMessage = "⚠️ \(msg)"
            shortcutMessageIsError = true
        case .failed(_, let msg):
            shortcutMessage = "⚠️ \(msg)"
            shortcutMessageIsError = true
        }

        (NSApp.delegate as? AppDelegate)?.menuBarController?.rebuildMenu()
    }

    func commitKeyboardUnlockShortcut(code: UInt32, mods: UInt32) {
        Preferences.shared.keyboardUnlockKeyCode = code
        Preferences.shared.keyboardUnlockKeyModifiers = mods
        keyboardUnlockShortcutDescription = Preferences.shared.keyboardUnlockShortcutDescription
        recordingTarget = nil
        shortcutMessage = "✓ Keyboard unlock shortcut updated to \(keyboardUnlockShortcutDescription)"
        shortcutMessageIsError = false
        (NSApp.delegate as? AppDelegate)?.menuBarController?.rebuildMenu()
    }

    func applyPreset(_ preset: Preferences.ShortcutPreset) {
        commitShortcut(code: preset.keyCode, mods: preset.modifiers)
    }

    func runDiagnostics() {
        let ax = PermissionsManager.shared.hasAccessibility
        let smStatus: String
        if #available(macOS 13.0, *) {
            smStatus = "\(SMAppService.mainApp.status)"
        } else {
            smStatus = "N/A"
        }

        var lines = [
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Accessibility Granted: \(ax ? "YES" : "NO")",
            "Start Cleaning Shortcut: \(Preferences.shared.hotKeyDescription)",
            "Keyboard Unlock Shortcut: \(Preferences.shared.keyboardUnlockShortcutDescription)",
            "Launch At Login Enabled: \(LaunchAtLoginManager.shared.isEnabled ? "YES" : "NO")",
            "SMAppService Status: \(smStatus)",
            "HotKey Registration: \(HotKeyManager.shared.lastResult.message)",
            "Block Cursor & Gestures: \(Preferences.shared.blockCursorAndGestures ? "ENABLED (Full Lockdown)" : "DISABLED (Cursor Allowed)")"
        ]
        if let ctrl = (NSApp.delegate as? AppDelegate)?.trackpadController {
            lines.append("Trackpad State: \(ctrl.state.displayTitle)")
        }
        diagnosticResult = lines.joined(separator: "\n")
    }

    func resetToDefaults() {
        Preferences.shared.resetToDefaults()
        blockCursorAndGestures = true
        showMenuBarIcon = true
        recordingTarget = nil
        shortcutDescription = Preferences.shared.hotKeyDescription
        keyboardUnlockShortcutDescription = Preferences.shared.keyboardUnlockShortcutDescription
        shortcutMessage = "✓ Reset to ⌃⌥⌘T to start and ⌃⌥⌘K to unlock"
        shortcutMessageIsError = false
        HotKeyManager.shared.register()
        (NSApp.delegate as? AppDelegate)?.menuBarController?.rebuildMenu()
    }

    func resetPermissionCache() {
        PermissionsManager.shared.resetPermissions()
        refresh()
    }
}
