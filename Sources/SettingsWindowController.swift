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
            // ── Status Overview ───────────────────────────────────────────────
            Section("Status") {
                LabeledContent("Trackpad Input") {
                    Text(vm.stateDescription)
                        .fontWeight(.medium)
                }
                LabeledContent("Active Shortcut") {
                    Text(vm.shortcutDescription)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(6)
                }
                LabeledContent("Launch on Startup") {
                    Text(vm.launchAtLogin ? "Enabled" : "Disabled")
                        .foregroundColor(vm.launchAtLogin ? .green : .secondary)
                }
            }

            // ── Shortcut Configuration ────────────────────────────────────────
            Section("Keyboard Shortcut Configuration") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Toggle Shortcut:")
                            .fontWeight(.medium)
                        Spacer()

                        if vm.isRecording {
                            // Active recorder field
                            ShortcutRecorderField(
                                displayText: vm.recorderDisplayText,
                                isRecording: vm.isRecording,
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

                    if vm.isRecording {
                        HStack(spacing: 4) {
                            Image(systemName: "record.circle.fill")
                                .foregroundColor(.red)
                            Text("Listening for key combination… Press any shortcut with modifiers (⌘, ⌥, ⌃, ⇧). Press Esc to cancel.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 2)
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

                    Text("The shortcut operates system-wide using Carbon RegisterEventHotKey. It works without Accessibility permissions and survives trackpad disable.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            // ── Trackpad Suppression Mode ─────────────────────────────────────
            Section("Trackpad Suppression Mode") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Block Cursor Movement & Gestures", isOn: $vm.blockCursorAndGestures)
                        .toggleStyle(.switch)

                    Text("Controls whether cursor movement and multi-touch gestures (swipes, pinch-to-zoom, rotate) are completely blocked when the trackpad is disabled.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if vm.blockCursorAndGestures {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill").foregroundColor(.accentColor)
                            Text("Full Lockdown: Cursor will NOT move, gestures will NOT work, and clicks/scrolls are blocked.")
                                .font(.caption2)
                                .foregroundColor(.accentColor)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.open.fill").foregroundColor(.secondary)
                            Text("Partial Mode: Clicks and scrolls are blocked, but cursor movement is allowed.")
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
                    Text("Accessibility allows creating the event tap; Input Monitoring allows dropping events. Both are required for trackpad suppression.")
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

            // ── Safe Recovery ─────────────────────────────────────────────────
            Section("Emergency Recovery") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("If the trackpad is disabled and you need to restore control:")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("1. Press the toggle shortcut (\(vm.shortcutDescription)) to immediately re-enable.")
                    Text("2. Press ⌘Q in this window or press ⌃⌥⌘Q to quit the app.")
                    Text("3. Open Terminal via Spotlight (⌘Space) and run: killall TrackpadToggle")
                    Text("4. Restart your Mac — trackpad input is unconditionally restored at reboot.")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 480, minHeight: 520)
        .onAppear { vm.refresh() }
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
    @Published var axGranted = false
    @Published var stateDescription = ""
    @Published var shortcutDescription = Preferences.shared.hotKeyDescription
    @Published var isRecording = false
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
            (NSApp.delegate as? AppDelegate)?.menuBarController?.rebuildMenu()
        }
    }

    var recorderDisplayText: String {
        isRecording ? "Press keys…" : shortcutDescription
    }

    func refresh() {
        axGranted = PermissionsManager.shared.hasAccessibility
        shortcutDescription = Preferences.shared.hotKeyDescription
        launchAtLogin = LaunchAtLoginManager.shared.isEnabled
        blockCursorAndGestures = Preferences.shared.blockCursorAndGestures
        if let ctrl = (NSApp.delegate as? AppDelegate)?.trackpadController {
            stateDescription = ctrl.state.displayTitle
        }
    }
    func startRecording() {
        isRecording = true
        shortcutMessage = nil
    }

    func cancelRecording() {
        isRecording = false
        shortcutMessage = nil
    }

    func commitShortcut(code: UInt32, mods: UInt32) {
        Preferences.shared.hotKeyCode = code
        Preferences.shared.hotKeyModifiers = mods
        shortcutDescription = Preferences.shared.hotKeyDescription
        isRecording = false

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
            "Active Shortcut: \(Preferences.shared.hotKeyDescription)",
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
        shortcutDescription = Preferences.shared.hotKeyDescription
        blockCursorAndGestures = true
        isRecording = false
        shortcutMessage = "✓ Reset to default shortcut (⌃⌥⌘T)"
        shortcutMessageIsError = false
        HotKeyManager.shared.register()
        (NSApp.delegate as? AppDelegate)?.menuBarController?.rebuildMenu()
    }

    func resetPermissionCache() {
        PermissionsManager.shared.resetPermissions()
        refresh()
    }
}
