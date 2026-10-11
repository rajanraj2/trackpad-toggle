// HotKeyManager.swift
// Global keyboard shortcut registration via Carbon RegisterEventHotKey.
//
// WHY CARBON?
// ────────────
// Carbon RegisterEventHotKey works globally and does NOT require Accessibility
// or Input Monitoring TCC permissions. It starts cleaning mode from any app.
// The separate keyboard-unlock shortcut is handled inside the active event tap
// so its key press is consumed instead of reaching the frontmost application.
//
// Alternative (NSEvent.addGlobalMonitorForEvents) requires Accessibility, which would
// create a circular dependency: if permissions are revoked the shortcut also stops.
//
// Carbon hot keys have existed since Mac OS X 10.0 and remain supported on macOS 27.

import Carbon
import AppKit
import os.log

private let logger = Logger(subsystem: "com.powertools.trackpadtoggle", category: "HotKeyManager")

// Carbon event handler type ID and creator for our hot key group.
private let kHotKeyEventClass: OSType = OSType(kEventClassKeyboard)
private let kHotKeyEventKind: UInt32  = UInt32(kEventHotKeyPressed)

/// Unique Carbon hot key IDs.
private let kTrackpadHotKeyID: UInt32 = 1
private let kFullLockHotKeyID: UInt32 = 2
enum HotKeyRegistrationResult: Equatable {
    case success
    case conflict(String)
    case failed(OSStatus, String)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .success:
            return "Shortcut registered successfully."
        case .conflict(let msg):
            return msg
        case .failed(let code, let msg):
            return "Failed to register shortcut (OSStatus \(code)): \(msg)"
        }
    }
}

final class HotKeyManager {
    static let shared = HotKeyManager()
    private init() {}

    /// Called when the trackpad-only hotkey fires.
    var onTrackpadHotKey: (() -> Void)?
    /// Called when the full lock (trackpad + keyboard) hotkey fires.
    var onFullLockHotKey: (() -> Void)?
    /// Legacy alias for trackpad-only hotkey.
    var onHotKey: (() -> Void)? {
        get { onTrackpadHotKey }
        set { onTrackpadHotKey = newValue }
    }

    private(set) var lastResult: HotKeyRegistrationResult = .success

    private var trackpadHotKeyRef: EventHotKeyRef?
    private var fullLockHotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Registers both configured shortcuts as Carbon EventHotKeys.
    /// Call again after the user changes either preferred shortcut.
    @discardableResult
    func register() -> HotKeyRegistrationResult {
        unregister()

        // Install the Carbon event handler once (idempotent on subsequent calls).
        installHandlerIfNeeded()

        // 1. Register Trackpad-only shortcut (Default: ⌃⌥⌘T)
        let code1 = Preferences.shared.hotKeyCode
        let mods1 = Preferences.shared.hotKeyModifiers
        let keyID1 = EventHotKeyID(signature: OSType(0x5454474C), // 'TTGL'
                                   id: kTrackpadHotKeyID)

        var hkRef1: EventHotKeyRef?
        let status1 = RegisterEventHotKey(
            code1,
            mods1,
            keyID1,
            GetApplicationEventTarget(),
            0,
            &hkRef1
        )
        if status1 == noErr {
            trackpadHotKeyRef = hkRef1
            logger.info("Trackpad hot key registered: \(Preferences.shared.hotKeyDescription)")
        } else {
            logger.warning("RegisterEventHotKey for trackpad failed: OSStatus=\(status1)")
        }

        // 2. Register Full Lock (Trackpad + Keyboard) shortcut (Default: ⌃⌥⌘K)
        let code2 = Preferences.shared.keyboardUnlockKeyCode
        let mods2 = Preferences.shared.keyboardUnlockKeyModifiers
        let keyID2 = EventHotKeyID(signature: OSType(0x5454474C), // 'TTGL'
                                   id: kFullLockHotKeyID)

        var hkRef2: EventHotKeyRef?
        let status2 = RegisterEventHotKey(
            code2,
            mods2,
            keyID2,
            GetApplicationEventTarget(),
            0,
            &hkRef2
        )
        if status2 == noErr {
            fullLockHotKeyRef = hkRef2
            logger.info("Full lock hot key registered: \(Preferences.shared.keyboardUnlockShortcutDescription)")
        } else {
            logger.warning("RegisterEventHotKey for full lock failed: OSStatus=\(status2)")
        }

        if status1 == noErr && status2 == noErr {
            lastResult = .success
            return .success
        } else if status1 == -9878 || status2 == -9878 {
            let res = HotKeyRegistrationResult.conflict("A shortcut is already reserved by macOS or another application.")
            lastResult = res
            return res
        } else {
            let errCode = status1 != noErr ? status1 : status2
            let res = HotKeyRegistrationResult.failed(errCode, "System error \(errCode).")
            lastResult = res
            return res
        }
    }

    func unregister() {
        if let ref = trackpadHotKeyRef {
            UnregisterEventHotKey(ref)
            trackpadHotKeyRef = nil
        }
        if let ref = fullLockHotKeyRef {
            UnregisterEventHotKey(ref)
            fullLockHotKeyRef = nil
        }
        logger.info("Hot keys unregistered")
    }
    // MARK: – Carbon event handler

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind:  UInt32(kEventHotKeyPressed))

        // Bridge self into the C handler via UnsafeMutableRawPointer.
        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        // InstallApplicationEventHandler is a C macro (unavailable in Swift).
        // Expand it: InstallEventHandler(GetApplicationEventTarget(), handler, count, specs, data, ref)
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, theEvent, userData) -> OSStatus in
                guard let ptr = userData else { return OSStatus(eventNotHandledErr) }
                let mgr = Unmanaged<HotKeyManager>.fromOpaque(ptr).takeUnretainedValue()

                var hkID = EventHotKeyID()
                GetEventParameter(theEvent,
                                  EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID),
                                  nil,
                                  MemoryLayout<EventHotKeyID>.size,
                                  nil,
                                  &hkID)

                if hkID.id == kTrackpadHotKeyID {
                    DispatchQueue.main.async { mgr.onTrackpadHotKey?() }
                } else if hkID.id == kFullLockHotKeyID {
                    DispatchQueue.main.async { mgr.onFullLockHotKey?() }
                }
                return noErr
            },
            1,
            &spec,
            selfPtr,
            &handlerRef
        )
    }
}
