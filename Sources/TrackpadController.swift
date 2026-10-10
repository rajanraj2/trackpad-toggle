// TrackpadController.swift
// Protocol + CGEventTap-based implementation that suppresses built-in trackpad input.
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
import os.log

private let logger = Logger(subsystem: "com.powertools.trackpadtoggle", category: "TrackpadController")

// MARK: – Protocol

protocol TrackpadControlling: AnyObject {
    var state: TrackpadState { get }
    var onStateChange: ((TrackpadState) -> Void)? { get set }
    /// Disable the trackpad. Throws on permission failure or tap creation error.
    func disable() throws
    /// Re-enable the trackpad by removing the event tap.
    func enable()
    /// Toggle between enabled and disabled.
    func toggle() throws
}

// MARK: – CGEventTap Implementation

/// Event types that originate from the trackpad and should be suppressed.
private func makeSuppressedEventMask() -> CGEventMask {
    let types: [CGEventType] = [
        .mouseMoved,
        .leftMouseDown,
        .leftMouseUp,
        .leftMouseDragged,
        .rightMouseDown,
        .rightMouseUp,
        .rightMouseDragged,
        .otherMouseDown,
        .otherMouseUp,
        .otherMouseDragged,
        .scrollWheel
    ]
    return types.reduce(CGEventMask(0)) { mask, type in
        mask | (CGEventMask(1) << CGEventMask(type.rawValue))
    }
}
private let suppressedEventMask: CGEventMask = makeSuppressedEventMask()
final class CGEventTapController: TrackpadControlling {

    private(set) var state: TrackpadState = .enabled {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((TrackpadState) -> Void)?

    /// The installed mach port backing the CGEventTap.
    private var tapPort: CFMachPort?
    /// The run loop source that feeds events into our callback.
    private var tapSource: CFRunLoopSource?

    // MARK: – Public interface

    func enable() {
        removeTap()
        state = .enabled
        logger.info("Trackpad enabled (event tap removed)")
    }

    func disable() throws {
        guard PermissionsManager.shared.hasAccessibility else {
            state = .permissionRequired
            throw TrackpadError.permissionRequired
        }
        state = .transitioning
        do {
            try installTap()
            state = .disabled
            logger.info("Trackpad disabled (event tap installed)")
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func toggle() throws {
        switch state {
        case .enabled:             try disable()
        case .disabled:            enable()
        case .transitioning:       break   // ignore rapid keypresses mid-transition
        case .permissionRequired:  throw TrackpadError.permissionRequired
        case .failed:              try disable()   // retry after failure
        case .unsupported:         throw TrackpadError.unsupported
        }
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

    deinit { removeTap() }
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

    // The OS disables a passive tap that times out. Re-enable and continue.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        controller.tapWasDisabledByOS()
        return nil
    }

    // ── Device discrimination heuristics ──────────────────────────────────────
    //
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
    // External USB/Bluetooth mice produce subtype 0 with pressure 0.
    // This heuristic is best-effort; see README limitations section.
    let subtype  = event.getIntegerValueField(.mouseEventSubtype)
    let pressure = event.getIntegerValueField(.mouseEventPressure)
    if subtype == 0 && pressure == 0 {
        return Unmanaged.passRetained(event) // likely an external mouse → pass through
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
