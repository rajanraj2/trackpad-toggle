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

/// Unique Carbon hot key ID used to correlate press events back to our registration.
private let kHotKeyID: UInt32 = 1

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

    /// Called when the registered hotkey fires.
    var onHotKey: (() -> Void)?
    private(set) var lastResult: HotKeyRegistrationResult = .success

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    // MARK: – Registration

    /// Registers the configured shortcut as a Carbon EventHotKey.
    /// Call again after the user changes their preferred shortcut.
    @discardableResult
    func register() -> HotKeyRegistrationResult {
        unregister()

        let code  = Preferences.shared.hotKeyCode
        let mods  = Preferences.shared.hotKeyModifiers
        let keyID = EventHotKeyID(signature: OSType(0x5454474C), // 'TTGL'
                                  id: kHotKeyID)

        // Install the Carbon event handler once (idempotent on subsequent calls).
        installHandlerIfNeeded()

        var hkRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            code,
            mods,
            keyID,
            GetApplicationEventTarget(),
            0,
            &hkRef
        )
        if status == noErr {
            hotKeyRef = hkRef
            lastResult = .success
            logger.info("Hot key registered: code=\(code) mods=\(mods) → \(Preferences.shared.hotKeyDescription)")
            return .success
        } else if status == -9878 /* eventHotKeyExistsErr */ {
            let res = HotKeyRegistrationResult.conflict("This shortcut is already reserved by macOS or another application.")
            lastResult = res
            logger.error("RegisterEventHotKey conflict: OSStatus=\(status)")
            return res
        } else {
            let res = HotKeyRegistrationResult.failed(status, "System error \(status).")
            lastResult = res
            logger.error("RegisterEventHotKey failed: OSStatus=\(status)")
            return res
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
            logger.info("Hot key unregistered")
        }
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

                if hkID.id == kHotKeyID {
                    DispatchQueue.main.async { mgr.onHotKey?() }
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
