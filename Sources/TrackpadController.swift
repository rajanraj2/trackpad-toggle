// TrackpadController.swift
// Protocol + CGEventTap-based implementation that suppresses built-in trackpad and keyboard input.
//
// MECHANISM SELECTION RATIONALE
// ──────────────────────────────
// Three mechanisms were evaluated:
//
//  1. IOHIDManager seize (kIOHIDOptionsTypeSeizeDevice) — requires root on macOS 27.
//     Result: kIOReturnNotPrivileged. Eliminated.
//
//  2. MultitouchSupport.framework MTDeviceStop — stops the multitouch stream for the
//     calling process only. Other clients (WindowServer) are unaffected. Eliminated.
//
//  3. CGEventTap at kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault
//     (active/suppression mode) — intercepts synthesised HID events before they are
//     distributed to any application. Requires Accessibility + Input Monitoring TCC.
//     CHOSEN. Works on macOS 14+ on Apple Silicon without root or SIP changes.
//
// WHAT IS SUPPRESSED
// ──────────────────
// ✅ Pointer movement
// ✅ Physical clicks (left, right, other)
// ✅ Tap-to-click (synthesised as left-click at HID layer)
// ✅ Momentum scrolling / two-finger scroll
// ✅ Click+drag
// ✅ Keyboard key-down, key-up, modifier, and system-defined key events
// ⚠️ System-level multitouch gestures (Mission Control, Exposé, Launchpad swipes)
//    These are processed inside WindowServer from raw MultitouchSupport data before
//    CGEventTap sees them. They are NOT fully suppressed by this mechanism.
//
// DEVICE DISCRIMINATION
// ─────────────────────
// CGEventTap does not expose a stable per-device source identifier in a public API.
// We use two heuristics to pass external-mouse events through:
//   • Scroll events: kCGScrollWheelEventIsContinuous == 0 → external scroll wheel → pass
//   • Pointer events: kCGMouseEventSubtype != 0 or pressure > 0 → trackpad → block
//     (external USB/Bluetooth mice produce subtype 0 with pressure 0)
// If an external mouse is connected its scroll wheel and buttons should continue to
// function. Pointer movement from external mice may also be affected on some
// configurations; see README for details.

import AppKit
import ApplicationServices
import Carbon
import os.log

private let logger = Logger(subsystem: "com.powertools.trackpadtoggle", category: "TrackpadController")

// MARK: – Protocol

protocol TrackpadControlling: AnyObject {
    var state: TrackpadState { get }
    var onStateChange: ((TrackpadState) -> Void)? { get set }
    /// Called when the configured full-lock (trackpad + keyboard) shortcut fires.
    var onFullLockShortcut: (() -> Void)? { get set }
    var onKeyboardUnlockShortcut: (() -> Void)? { get set }
    /// Called when the configured trackpad-only shortcut fires inside event tap.
    var onTrackpadShortcut: (() -> Void)? { get set }
    func disable(mode: LockState) throws
    /// Disable trackpad only (default).
    func disable() throws
    /// Re-enable all input by removing the event tap.
    func enable()
    /// Toggle trackpad-only mode on/off.
    func toggleTrackpadOnly() throws
    /// Toggle full-lock (trackpad + keyboard) mode on/off.
    func toggleFullLock() throws
    /// Toggle between enabled and disabled (trackpad only).
    func toggle() throws
    /// Updates cursor association dynamically if mode changes while disabled.
    func updateSuppressionMode()
}

// MARK: – CGEventTap Implementation

/// Event types suppressed while cleaning mode is active.
/// Covers trackpad pointer input, gestures, and keyboard actions.
private func makeSuppressedEventMask() -> CGEventMask {
    let rawValues: [UInt32] = [
        CGEventType.leftMouseDown.rawValue,         // 1
        CGEventType.leftMouseUp.rawValue,           // 2
        CGEventType.rightMouseDown.rawValue,        // 3
        CGEventType.rightMouseUp.rawValue,          // 4
        CGEventType.mouseMoved.rawValue,            // 5
        CGEventType.leftMouseDragged.rawValue,      // 6
        CGEventType.rightMouseDragged.rawValue,     // 7
        CGEventType.keyDown.rawValue,               // 10
        CGEventType.keyUp.rawValue,                 // 11
        CGEventType.flagsChanged.rawValue,          // 12
        14,                                         // system-defined (media / function) key event
        CGEventType.scrollWheel.rawValue,           // 22
        CGEventType.tabletPointer.rawValue,         // 23
        CGEventType.tabletProximity.rawValue,       // 24
        CGEventType.otherMouseDown.rawValue,        // 25
        CGEventType.otherMouseUp.rawValue,          // 26
        CGEventType.otherMouseDragged.rawValue,     // 27
        18,                                         // rotate gesture
        19,                                         // beginGesture
        20,                                         // endGesture
        29,                                         // gesture event
        30,                                         // magnify (pinch to zoom)
        31,                                         // swipe gesture
        32,                                         // smartMagnify
        33,                                         // quickLook
        34                                          // pressure (Force Touch)
    ]
    return rawValues.reduce(CGEventMask(0)) { mask, val in
        mask | (CGEventMask(1) << CGEventMask(val))
    }
}
private let suppressedEventMask: CGEventMask = makeSuppressedEventMask()
final class CGEventTapController: TrackpadControlling {

    private(set) var state: TrackpadState = .enabled {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((TrackpadState) -> Void)?
    var onFullLockShortcut: (() -> Void)?
    var onKeyboardUnlockShortcut: (() -> Void)? {
        get { onFullLockShortcut }
        set { onFullLockShortcut = newValue }
    }
    var onTrackpadShortcut: (() -> Void)?
    /// The installed mach port backing the CGEventTap.
    private var tapPort: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private(set) var lockedCursorPosition: CGPoint = .zero

    // MARK: – Public interface

    func enable() {
        removeTap()
        // Reconnect hardware mouse movement to on-screen cursor
        CGAssociateMouseAndMouseCursorPosition(1)
        state = .enabled
        logger.info("Trackpad enabled (event tap removed, cursor re-associated)")
    }

    func disable(mode: LockState) throws {
        state = .transitioning
        do {
            try installTap()

            if Preferences.shared.blockCursorAndGestures {
                let currentPos = CGEvent(source: nil)?.location ?? .zero
                self.lockedCursorPosition = currentPos
                CGAssociateMouseAndMouseCursorPosition(0)
                CGWarpMouseCursorPosition(currentPos)
                logger.info("Cursor frozen at \(String(describing: currentPos))")
            }

            state = .disabled(locks: mode)
            logger.info("Disabled input with locks: \(String(describing: mode))")
        } catch {
            state = .permissionRequired
            throw error
        }
    }

    func disable() throws {
        try disable(mode: LockState(trackpadLocked: true, keyboardLocked: false))
    }
    func updateSuppressionMode() {
        guard case .disabled = state else {
            CGAssociateMouseAndMouseCursorPosition(1)
            return
        }
        if Preferences.shared.blockCursorAndGestures {
            let currentPos = CGEvent(source: nil)?.location ?? .zero
            self.lockedCursorPosition = currentPos
            CGAssociateMouseAndMouseCursorPosition(0)
            CGWarpMouseCursorPosition(currentPos)
            logger.info("Suppression mode updated: cursor frozen at \(String(describing: currentPos))")
        } else {
            CGAssociateMouseAndMouseCursorPosition(1)
            logger.info("Suppression mode updated: cursor movement allowed")
        }
    }

    func toggleTrackpadOnly() throws {
        switch state {
        case .enabled:
            try disable(mode: LockState(trackpadLocked: true, keyboardLocked: false))
        case .disabled(let locks):
            if locks.trackpadLocked {
                // Trackpad was already locked; unlock it while keeping keyboard state
                var newLocks = locks
                newLocks.trackpadLocked = false
                if newLocks.keyboardLocked {
                    state = .disabled(locks: newLocks)
                } else {
                    enable()
                }
            } else {
                // Trackpad was enabled; lock it
                try disable(mode: LockState(trackpadLocked: true, keyboardLocked: false))
            }
        case .transitioning:
            break
        case .permissionRequired:
            throw TrackpadError.permissionRequired
        case .failed:
            try disable(mode: LockState(trackpadLocked: true, keyboardLocked: false))
        case .unsupported:
            throw TrackpadError.unsupported
        }
    }

    // Duplicate removed.

    func toggleFullLock() throws {
        switch state {
        case .enabled:
            try disable(mode: LockState(trackpadLocked: true, keyboardLocked: true))
        case .disabled(let locks):
            if locks.keyboardLocked {
                // Re-enable everything immediately
                enable()
            } else {
                // Transition to locking both
                try disable(mode: LockState(trackpadLocked: true, keyboardLocked: true))
            }
        case .transitioning:
            break
        case .permissionRequired:
            throw TrackpadError.permissionRequired
        case .failed:
            try disable(mode: LockState(trackpadLocked: true, keyboardLocked: true))
        case .unsupported:
            throw TrackpadError.unsupported
        }
    }
    func toggle() throws {
        try toggleTrackpadOnly()
    }


    // MARK: – Tap lifecycle

    private func installTap() throws {
        // Unmanaged bridge so the C callback can call methods on self.
        let selfPtr = Unmanaged.passRetained(self)

        let port = CGEvent.tapCreate(
            tap: .cghidEventTap,           // raw HID layer, before gesture recognition
            place: .headInsertEventTap,    // first in the chain — we see events before others
            options: .defaultTap,          // active tap: callback can drop events
            eventsOfInterest: suppressedEventMask,
            callback: eventTapCallback,
            userInfo: selfPtr.toOpaque()
        )

        if let port = port {
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
            self.tapPort   = port
            self.tapSource = src
            logger.debug("Event tap installed, port=\(String(describing: port))")
        } else {
            selfPtr.release()
            // CGEventTapCreate returns nil either when Accessibility is missing or when
            // Input Monitoring has not been granted. Distinguish by re-checking AX.
            if PermissionsManager.shared.hasAccessibility {
                // AX is granted but tap still failed → Input Monitoring missing
                throw TrackpadError.inputMonitoringRequired
            } else {
                throw TrackpadError.permissionRequired
            }
        }
    }

    private func removeTap() {
        if let src = tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            self.tapSource = nil
        }
        if let port = tapPort {
            // Disable before release to flush any pending events.
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
            self.tapPort = nil
        }
    }

    /// Called by the OS when the event tap is disabled (e.g. the process was too slow).
    func tapWasDisabledByOS() {
        logger.warning("Event tap was disabled by the OS — re-enabling")
        if let port = tapPort {
            CGEvent.tapEnable(tap: port, enable: true)
        }
    }

    /// Consumes keyboard events while in full-lock mode and checks for shortcuts.
    func handleKeyboardEvent(type: CGEventType, event: CGEvent) {
        if matchesFullLockShortcut(type: type, event: event) {
            DispatchQueue.main.async { [weak self] in
                guard let self, case .disabled = self.state else { return }
                self.onFullLockShortcut?()
            }
        } else if matchesTrackpadShortcut(type: type, event: event) {
            DispatchQueue.main.async { [weak self] in
                guard let self, case .disabled = self.state else { return }
                self.onTrackpadShortcut?()
            }
        }
    }

    /// True when the event is exactly the configured trackpad chord on key-down.
    func matchesTrackpadShortcut(type: CGEventType, event: CGEvent) -> Bool {
        guard type == .keyDown else { return false }
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        return keyCode == Preferences.shared.hotKeyCode
            && carbonModifiers(from: event.flags) == Preferences.shared.hotKeyModifiers
    }

    /// True when the event is exactly the configured full-lock chord on key-down.
    func matchesFullLockShortcut(type: CGEventType, event: CGEvent) -> Bool {
        guard type == .keyDown else { return false }
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        return keyCode == Preferences.shared.keyboardUnlockKeyCode
            && carbonModifiers(from: event.flags) == Preferences.shared.keyboardUnlockKeyModifiers
    }

    func matchesKeyboardUnlockShortcut(type: CGEventType, event: CGEvent) -> Bool {
        matchesFullLockShortcut(type: type, event: event)
    }

    private func carbonModifiers(from flags: CGEventFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.maskControl) { modifiers |= UInt32(controlKey) }
        if flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }
        if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    deinit {
        removeTap()
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}

// MARK: – C-level callback (cannot be a closure capturing self)

/// Returns nil to consume/suppress the event; returns the event unmodified to pass it through.
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let ptr = userInfo else { return Unmanaged.passRetained(event) }
    let controller = Unmanaged<CGEventTapController>.fromOpaque(ptr).takeUnretainedValue()
    // (Settings window pass-through removed — it was treating the wrong symptom.)

    // The OS disables a passive tap that times out. Re-enable and continue.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        controller.tapWasDisabledByOS()
        return nil
    }

    if type == .keyDown || type == .keyUp || type == .flagsChanged || type.rawValue == 14 {
        if case .disabled(let locks) = controller.state, locks.keyboardLocked {
            controller.handleKeyboardEvent(type: type, event: event)
            return nil
        } else {
            return Unmanaged.passRetained(event)
        }
    }
    // ── Suppression logic based on user configuration ────────────────────────
    //
    // When blockCursorAndGestures is enabled (default):
    // Completely drops ALL trackpad events in the mask and locks cursor sprite.
    // Cursor will NOT move, gestures will NOT work, clicks & scrolls will NOT work.
    if Preferences.shared.blockCursorAndGestures {
        CGWarpMouseCursorPosition(controller.lockedCursorPosition)
        return nil
    }
    // Partial / Standard mode (when user explicitly unchecks blockCursorAndGestures):
    // Cursor movement is permitted through.
    if type == .mouseMoved {
        return Unmanaged.passRetained(event)
    }

    // Scroll events: IsContinuous = 1 means trackpad or Magic Mouse momentum scroll.
    // Discrete scrolling (external scroll wheel) returns 0 → pass through.
    if type == .scrollWheel {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
        if isContinuous == 0 {
            return Unmanaged.passRetained(event) // external mouse scroll wheel
        }
        return nil // trackpad scroll → suppress
    }

    // Pointer events: trackpad events typically carry subtype ≠ 0 or non-zero pressure.
    let subtype  = event.getIntegerValueField(.mouseEventSubtype)
    let pressure = event.getIntegerValueField(.mouseEventPressure)
    if subtype == 0 && pressure == 0 {
        return Unmanaged.passRetained(event) // external mouse → pass through
    }
    return nil // trackpad event → suppress
}

// MARK: – Errors

enum TrackpadError: LocalizedError {
    case permissionRequired
    case inputMonitoringRequired
    case unsupported

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            return "Accessibility permission is required. Grant it in System Settings → Privacy & Security → Accessibility."
        case .inputMonitoringRequired:
            return "Input Monitoring permission is required. Grant it in System Settings → Privacy & Security → Input Monitoring."
        case .unsupported:
            return "This device does not support trackpad toggle."
        }
    }
}
