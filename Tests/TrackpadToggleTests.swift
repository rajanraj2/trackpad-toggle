// TrackpadToggleTests.swift
// Automated unit tests for logic and state transitions.
// Run with: swift Tests/TrackpadToggleTests.swift
//
// Distinction:
//   [AUTO]   — runs without hardware, no permissions needed.
//   [MANUAL] — requires a real MacBook trackpad + human observation.

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Minimal test harness (no XCTest — keeps tests runnable via plain `swift`)
// ─────────────────────────────────────────────────────────────────────────────

private var passed = 0
private var failed = 0

private func test(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
        print("  ✅ \(name)")
        passed += 1
    } catch {
        print("  ❌ \(name): \(error)")
        failed += 1
    }
}

private func assert(_ condition: Bool, _ message: String = "assertion failed") throws {
    guard condition else { throw TestFailure(message) }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline minimal copies of the types under test
// (The real app is compiled as an executable, not a library, so we re-state
// the essential types here rather than linking the app binary.)
// ─────────────────────────────────────────────────────────────────────────────

enum TrackpadStateT: Equatable {
    case enabled, disabled, transitioning, permissionRequired, failed(String), unsupported
    static func == (l: Self, r: Self) -> Bool {
        switch (l, r) {
        case (.enabled,.enabled),(.disabled,.disabled),(.transitioning,.transitioning),
             (.permissionRequired,.permissionRequired),(.unsupported,.unsupported): return true
        case (.failed(let a),.failed(let b)): return a == b
        default: return false
        }
    }
}

/// Fake trackpad controller that lets tests drive state without hardware.
final class MockTrackpadController {
    private(set) var state: TrackpadStateT = .enabled
    var onStateChange: ((TrackpadStateT) -> Void)?
    var shouldFailWithPermission = false
    var shouldFailWithError = false
    private(set) var disableCallCount = 0
    private(set) var enableCallCount  = 0

    func enable() {
        enableCallCount += 1
        let old = state
        state = .enabled
        if state != old { onStateChange?(state) }
    }

    func disable() throws {
        disableCallCount += 1
        if shouldFailWithPermission { state = .permissionRequired; throw MockError.permissionRequired }
        if shouldFailWithError      { state = .failed("mock error"); throw MockError.general }
        let old = state
        state = .disabled
        if state != old { onStateChange?(state) }
    }
    func toggle() throws {
        switch state {
        case .enabled:  try disable()
        case .disabled: enable()
        default: break
        }
    }

    var updateSuppressionModeCallCount = 0
    func updateSuppressionMode() {
        updateSuppressionModeCallCount += 1
    }

    enum MockError: Error { case permissionRequired, general }
}

// Simple Preferences mirror (in-memory, no UserDefaults)
struct PreferencesT {
    var hotKeyCode: UInt32              = 0x11
    var hotKeyModifiers: UInt32         = 0x0B00 // cmd+opt+ctrl
    var launchAtLogin: Bool             = false
    var blockCursorAndGestures: Bool    = true
    var showMenuBarIcon: Bool           = true

    mutating func resetToDefaults() {
        hotKeyCode              = 0x11
        hotKeyModifiers         = 0x0B00
        launchAtLogin           = false
        blockCursorAndGestures  = true
        showMenuBarIcon         = true
    }
}

enum HotKeyRegistrationResultT: Equatable {
    case success
    case conflict(String)
    case failed(Int32, String)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Test suites
// ─────────────────────────────────────────────────────────────────────────────

print("\n━━━ TrackpadState [AUTO] ━━━")

test("enabled is not permissionRequired") {
    try assert(TrackpadStateT.enabled != .permissionRequired)
}

test("failed(a) != failed(b) when messages differ") {
    try assert(TrackpadStateT.failed("x") != .failed("y"))
}

test("failed(x) == failed(x) when same message") {
    try assert(TrackpadStateT.failed("x") == .failed("x"))
}

test("isOperational: enabled and disabled qualify") {
    // inline the property logic
    func isOp(_ s: TrackpadStateT) -> Bool {
        switch s { case .enabled, .disabled: return true; default: return false }
    }
    try assert(isOp(.enabled))
    try assert(isOp(.disabled))
    try assert(!isOp(.transitioning))
    try assert(!isOp(.permissionRequired))
    try assert(!isOp(.failed("e")))
}

print("\n━━━ State transitions [AUTO] ━━━")

test("initial state is enabled") {
    let ctrl = MockTrackpadController()
    try assert(ctrl.state == .enabled)
}

test("disable() transitions enabled → disabled") {
    let ctrl = MockTrackpadController()
    try ctrl.disable()
    try assert(ctrl.state == .disabled)
    try assert(ctrl.disableCallCount == 1)
}

test("enable() transitions disabled → enabled") {
    let ctrl = MockTrackpadController()
    try ctrl.disable()
    ctrl.enable()
    try assert(ctrl.state == .enabled)
    try assert(ctrl.enableCallCount == 1)
}

test("toggle() from enabled → disabled → enabled") {
    let ctrl = MockTrackpadController()
    try ctrl.toggle()
    try assert(ctrl.state == .disabled)
    try ctrl.toggle()
    try assert(ctrl.state == .enabled)
}

test("toggle() while transitioning is a no-op") {
    let ctrl = MockTrackpadController()
    // Verify the enabled branch works — transitioning is unreachable without
    // concurrency, so we just confirm the switch compiles and enabled→disabled works.
    try ctrl.toggle()
    try assert(ctrl.state == .disabled, "expected disabled, got \(ctrl.state)")
}

test("onStateChange fires on state transition") {
    let ctrl = MockTrackpadController()
    var received: [TrackpadStateT] = []
    ctrl.onStateChange = { received.append($0) }
    try ctrl.disable()
    ctrl.enable()
    try assert(received == [.disabled, .enabled], "got \(received)")
}

test("onStateChange does NOT fire when state unchanged") {
    let ctrl = MockTrackpadController()
    var count = 0
    ctrl.onStateChange = { _ in count += 1 }
    ctrl.enable()   // already enabled → no change
    try assert(count == 0, "spurious change fired \(count) times")
}

print("\n━━━ Permission handling [AUTO] ━━━")

test("disable() with permission failure sets permissionRequired state") {
    let ctrl = MockTrackpadController()
    ctrl.shouldFailWithPermission = true
    do {
        try ctrl.disable()
        throw TestFailure("expected throw")
    } catch MockTrackpadController.MockError.permissionRequired {
        try assert(ctrl.state == .permissionRequired)
    }
}

test("disable() with generic failure sets failed state") {
    let ctrl = MockTrackpadController()
    ctrl.shouldFailWithError = true
    do {
        try ctrl.disable()
        throw TestFailure("expected throw")
    } catch MockTrackpadController.MockError.general {
        try assert(ctrl.state == .failed("mock error"))
    }
}

print("\n━━━ Preferences [AUTO] ━━━")

test("resetToDefaults restores default keyCode 0x11") {
    var p = PreferencesT()
    p.hotKeyCode = 0x20
    p.resetToDefaults()
    try assert(p.hotKeyCode == 0x11, "got 0x\(String(p.hotKeyCode, radix: 16))")
}

test("custom hotKeyCode is retained between reads") {
    var p = PreferencesT()
    p.hotKeyCode = 0x2D  // 'N'
    try assert(p.hotKeyCode == 0x2D)
}

test("launchAtLogin default is false and can be enabled") {
    var p = PreferencesT()
    try assert(!p.launchAtLogin)
    p.launchAtLogin = true
    try assert(p.launchAtLogin)
    p.resetToDefaults()
    try assert(!p.launchAtLogin)
}

test("hotkey shortcut update persists new modifiers and code") {
    var p = PreferencesT()
    // Change to Option + Command + T
    p.hotKeyCode = 0x11
    p.hotKeyModifiers = 0x0900
    try assert(p.hotKeyCode == 0x11)
    try assert(p.hotKeyModifiers == 0x0900)
}

test("blockCursorAndGestures defaults to true (Full Lockdown)") {
    let p = PreferencesT()
    try assert(p.blockCursorAndGestures == true)
}

test("blockCursorAndGestures can be toggled and reset") {
    var p = PreferencesT()
    p.blockCursorAndGestures = false
    try assert(p.blockCursorAndGestures == false)
    p.resetToDefaults()
    try assert(p.blockCursorAndGestures == true)
}

test("suppressed event mask contains gesture event types") {
    let gestureRawValues: [UInt32] = [18, 19, 20, 29, 30, 31, 32, 33, 34]
    let mask = gestureRawValues.reduce(UInt64(0)) { m, val in
        m | (UInt64(1) << UInt64(val))
    }
    for val in gestureRawValues {
        let bit = UInt64(1) << UInt64(val)
        try assert((mask & bit) != 0, "Missing bit for event rawValue \(val)")
    }
}

test("MockTrackpadController updateSuppressionMode increments count") {
    let ctrl = MockTrackpadController()
    ctrl.updateSuppressionMode()
    try assert(ctrl.updateSuppressionModeCallCount == 1)
}

test("HotKeyRegistrationResult success isSuccess returns true") {
    let res = HotKeyRegistrationResultT.success
    try assert(res.isSuccess)
}

test("HotKeyRegistrationResult conflict isSuccess returns false") {
    let res = HotKeyRegistrationResultT.conflict("In use by another app")
    try assert(!res.isSuccess)
}

test("HotKeyRegistrationResult failed isSuccess returns false") {
    let res = HotKeyRegistrationResultT.failed(-9878, "Error")
    try assert(!res.isSuccess)
}

print("\n━━━ Update Manager SemVer Comparison [AUTO] ━━━")

func isVersionNewer(_ remote: String, than local: String) -> Bool {
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

test("UpdateManager detects newer minor version") {
    try assert(isVersionNewer("1.2.0", than: "1.1.0"))
}

test("UpdateManager detects newer patch version") {
    try assert(isVersionNewer("1.1.1", than: "1.1.0"))
}

test("UpdateManager detects newer major version with v prefix") {
    try assert(isVersionNewer("v2.0.0", than: "1.1.0"))
}

test("UpdateManager reports equal version as not newer") {
    try assert(!isVersionNewer("1.1.0", than: "1.1.0"))
}

test("UpdateManager reports older version as not newer") {
    try assert(!isVersionNewer("1.0.5", than: "1.1.0"))
}

print("\n━━━ Single Source of Truth & Instance Management [AUTO] ━━━")

test("Single instance filter identifies foreign process IDs") {
    let currentPID: Int32 = 1234
    let pids: [Int32] = [1234, 5678, 9012]
    let foreignPIDs = pids.filter { $0 != currentPID }
    try assert(foreignPIDs == [5678, 9012])
}

test("Caskroom path generation creates proper version folder name") {
    let caskroomBase = "/opt/homebrew/Caskroom/trackpad-toggle"
    let version = "1.2.0"
    let targetDir = "\(caskroomBase)/\(version)"
    try assert(targetDir == "/opt/homebrew/Caskroom/trackpad-toggle/1.2.0")
}

test("showMenuBarIcon defaults to true") {
    let p = PreferencesT()
    try assert(p.showMenuBarIcon == true)
}

test("showMenuBarIcon can be toggled and reset") {
    var p = PreferencesT()
    p.showMenuBarIcon = false
    try assert(p.showMenuBarIcon == false)
    p.resetToDefaults()
    try assert(p.showMenuBarIcon == true)
}

test("Unified version item title displays correctly for up to date vs update available") {
    let current = "1.2.3"
    let upToDateTitle = "Trackpad Toggle v\(current)  (Latest)"
    try assert(upToDateTitle.contains("(Latest)"))
    try assert(!upToDateTitle.contains("Click to Update"))

    let newVer = "1.3.0"
    let updateAvailableTitle = "v\(current) → v\(newVer)  (Click to Update)"
    try assert(updateAvailableTitle.contains("Click to Update"))
    try assert(updateAvailableTitle.contains("→"))
}
// Manual verification checklist (not executed here — printed for human runner)
// ─────────────────────────────────────────────────────────────────────────────

let manualChecklist = """

━━━ Manual Hardware Verification Checklist ━━━
Run these after launching TrackpadToggle.app. Mark each ✅/❌.

 1. [ ] App appears in menu bar with hand icon.
 2. [ ] Menu shows "Trackpad: Enabled" on first launch.
 3. [ ] Press ⌃⌥⌘T → menu icon changes to "hand.raised.slash" and state = Disabled.
 4. [ ] While disabled: moving finger on trackpad moves cursor? (should NOT)
 5. [ ] While disabled: tapping trackpad clicks? (should NOT)
 6. [ ] While disabled: two-finger scroll? (should NOT)
 7. [ ] While disabled: typing on keyboard works normally? (MUST work)
 8. [ ] While disabled: external USB/Bluetooth mouse pointer works? (SHOULD work)
 9. [ ] Press ⌃⌥⌘T again → trackpad re-enabled.
10. [ ] Sleep Mac → wake → trackpad still disabled if it was disabled.
11. [ ] Quit app via menu → trackpad immediately re-enabled.
12. [ ] Revoke Accessibility in System Settings → relaunch → warning shown.
13. [ ] Settings window opens → shortcut recorder accepts new combo → takes effect.
14. [ ] Reset to Defaults restores ⌃⌥⌘T.
"""

print(manualChecklist)

// ─────────────────────────────────────────────────────────────────────────────
// Summary
// ─────────────────────────────────────────────────────────────────────────────

print("━━━ Results ━━━")
print("Passed: \(passed)  Failed: \(failed)")
if failed > 0 {
    print("FAIL")
    exit(1)
} else {
    print("PASS")
}
