// SettingsWindowController.swift
// A compact NSWindow with SwiftUI content showing:
//   • Current operating mode and shortcut
//   • Permission status with open-settings buttons
//   • Shortcut recorder field
//   • Diagnostics / reset

import AppKit
import SwiftUI
import Carbon   // for cmdKey / optionKey / controlKey / shiftKey in RecorderTextField
import os.log

private let logger = Logger(subsystem: "com.powertools.trackpadtoggle", category: "Settings")

// MARK: – Settings window

final class SettingsWindowController: NSWindowController {

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Trackpad Toggle — Settings"
        window.isReleasedWhenClosed = false
        window.center()

        let contentView = SettingsView()
        window.contentView = NSHostingView(rootView: contentView)

        self.init(window: window)
    }
}

// MARK: – SwiftUI content

private struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()

    var body: some View {
        Form {
            // ── Status ────────────────────────────────────────────────────────
            Section("Current State") {
                LabeledContent("Trackpad", value: vm.stateDescription)
                LabeledContent("Shortcut", value: vm.shortcutDescription)
            }

            // ── Permissions ────────────────────────────────────────────────────
            Section("Permissions") {
                HStack {
                    Image(systemName: vm.axGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(vm.axGranted ? .green : .red)
                    Text("Accessibility")
                    Spacer()
                    if !vm.axGranted {
                        Button("Grant…") { PermissionsManager.shared.openAccessibilitySettings() }
                            .buttonStyle(.borderless)
                            .foregroundColor(.accentColor)
                    }
                }
                HStack {
                    Image(systemName: "info.circle.fill").foregroundColor(.secondary)
                    Text("Input Monitoring")
                    Spacer()
                    Button("Open Settings…") { PermissionsManager.shared.openInputMonitoringSettings() }
                        .buttonStyle(.borderless)
                        .foregroundColor(.accentColor)
                }
                Text("Both permissions are required. Tap creation failure indicates missing Input Monitoring access.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // ── Shortcut Recorder ─────────────────────────────────────────────
            Section("Keyboard Shortcut") {
                ShortcutRecorderRow(vm: vm)
                Text("Click the field and press your desired key combination.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Uses Carbon RegisterEventHotKey — works without Accessibility and survives trackpad disable.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // ── Diagnostics ────────────────────────────────────────────────────
            Section("Diagnostics") {
                LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                LabeledContent("Mechanism", value: "CGEventTap (kCGHIDEventTap)")
                LabeledContent("Hot key engine", value: "Carbon RegisterEventHotKey")
                Button("Run Diagnostics") { vm.runDiagnostics() }
                if let msg = vm.diagnosticResult {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }

            // ── Reset ─────────────────────────────────────────────────────────
            Section {
                Button("Reset to Defaults", role: .destructive) { vm.resetToDefaults() }
            }

            // ── Recovery info ─────────────────────────────────────────────────
            Section("Recovery") {
                Text("If the trackpad is disabled and you cannot re-enable it:")
                    .font(.caption).bold()
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Press the registered shortcut (\(vm.shortcutDescription)) to toggle.")
                    Text("2. Press ⌘Q to quit — the tap is removed on exit.")
                    Text("3. Open Terminal and run:  killall TrackpadToggle")
                    Text("4. Reboot — the trackpad always returns after a restart.")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 440, minHeight: 420)
        .onAppear { vm.refresh() }
    }
}

// MARK: – Shortcut recorder row
// Kept as a separate View that reads state from SettingsViewModel.

private struct ShortcutRecorderRow: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        HStack {
            Text("Shortcut")
            Spacer()
            // NSViewRepresentable wrapping a key-capture NSTextField.
            ShortcutRecorderField(
                displayText: vm.recorderDisplayText,
                isRecording: vm.isRecording,
                onCommit: { code, mods in
                    vm.commitShortcut(code: code, mods: mods)
                },
                onToggleRecording: {
                    vm.isRecording.toggle()
                }
            )
            .frame(width: 170, height: 26)
        }
    }
}

// MARK: – NSViewRepresentable shortcut field

private struct ShortcutRecorderField: NSViewRepresentable {
    var displayText: String
    var isRecording: Bool
    var onCommit: (UInt32, UInt32) -> Void
    var onToggleRecording: () -> Void

    func makeNSView(context: Context) -> RecorderTextField {
        let field = RecorderTextField()
        field.onCommit = onCommit
        field.onToggleRecording = onToggleRecording
        return field
    }

    func updateNSView(_ nsView: RecorderTextField, context: Context) {
        nsView.isInRecordingMode = isRecording
        nsView.updateDisplay(displayText)
    }
}

/// A custom NSTextField that captures the next keypress as a shortcut.
final class RecorderTextField: NSTextField {
    var onCommit: ((UInt32, UInt32) -> Void)?
    var onToggleRecording: (() -> Void)?

    var isInRecordingMode = false {
        didSet { refreshDisplay() }
    }

    private var savedDisplayText = Preferences.shared.hotKeyDescription

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBezeled    = true
        isEditable   = false
        isSelectable = false
        alignment    = .center
        wantsLayer   = true
        refreshDisplay()
    }
    required init?(coder: NSCoder) { fatalError() }

    func updateDisplay(_ text: String) {
        savedDisplayText = text
        if !isInRecordingMode { stringValue = text }
    }

    private func refreshDisplay() {
        stringValue = isInRecordingMode ? "Press shortcut…" : savedDisplayText
    }

    override func mouseDown(with event: NSEvent) {
        onToggleRecording?()
        if isInRecordingMode { window?.makeFirstResponder(self) }
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isInRecordingMode else { super.keyDown(with: event); return }

        let carbonMods = cocoaModsToCarbonMods(event.modifierFlags)
        let carbonCode = UInt32(event.keyCode)

        // Accept if at least one modifier is held, or it's a function key (≥ 0x60).
        guard carbonMods != 0 || event.keyCode >= 0x60 else { return }

        onCommit?(carbonCode, carbonMods)
    }

    private func cocoaModsToCarbonMods(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey)     }
        if flags.contains(.option)  { mods |= UInt32(optionKey)  }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey)   }
        return mods
    }
}

// MARK: – ViewModel

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var axGranted          = false
    @Published var stateDescription   = ""
    @Published var shortcutDescription = Preferences.shared.hotKeyDescription
    @Published var diagnosticResult: String?
    @Published var isRecording        = false

    var recorderDisplayText: String {
        isRecording ? "Press shortcut…" : shortcutDescription
    }

    func refresh() {
        axGranted          = PermissionsManager.shared.hasAccessibility
        shortcutDescription = Preferences.shared.hotKeyDescription
        if let ctrl = (NSApp.delegate as? AppDelegate)?.trackpadController {
            stateDescription = ctrl.state.displayTitle
        }
    }

    func runDiagnostics() {
        let ax  = PermissionsManager.shared.hasAccessibility
        let ver = ProcessInfo.processInfo.operatingSystemVersionString
        var lines = [
            "macOS: \(ver)",
            "Accessibility: \(ax ? "✅ granted" : "❌ missing")",
            "Input Monitoring: check System Settings (no public API query available)",
            "Shortcut: \(Preferences.shared.hotKeyDescription)",
        ]
        if let ctrl = (NSApp.delegate as? AppDelegate)?.trackpadController {
            lines.append("State: \(ctrl.state.displayTitle)")
        }
        diagnosticResult = lines.joined(separator: "\n")
    }

    func resetToDefaults() {
        Preferences.shared.resetToDefaults()
        shortcutDescription = Preferences.shared.hotKeyDescription
        HotKeyManager.shared.register()
        (NSApp.delegate as? AppDelegate)?.menuBarController?.rebuildMenu()
        objectWillChange.send()
    }

    func commitShortcut(code: UInt32, mods: UInt32) {
        Preferences.shared.hotKeyCode      = code
        Preferences.shared.hotKeyModifiers = mods
        shortcutDescription = Preferences.shared.hotKeyDescription
        isRecording = false
        HotKeyManager.shared.register()
        (NSApp.delegate as? AppDelegate)?.menuBarController?.rebuildMenu()
    }
}
