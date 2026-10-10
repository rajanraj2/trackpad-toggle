// HotKeyManager.swift
// Global keyboard shortcut registration via Carbon RegisterEventHotKey.
//
// WHY CARBON?
// ────────────
// Carbon RegisterEventHotKey works at the kernel event level and does NOT require
// the Accessibility or Input Monitoring TCC permissions. This means the recovery
// shortcut to re-enable the trackpad continues to fire even while our event tap is
// blocking trackpad input — regardless of whether other permissions have been granted.
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

final class HotKeyManager {
    static let shared = HotKeyManager()
    private init() {}

    /// Called when the registered hotkey fires.
    var onHotKey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    // MARK: – Registration

    /// Registers the configured shortcut as a Carbon EventHotKey.
    /// Call again after the user changes their preferred shortcut.
    func register() {
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
            logger.info("Hot key registered: code=\(code) mods=\(mods) → \(Preferences.shared.hotKeyDescription)")
        } else {
            logger.error("RegisterEventHotKey failed: OSStatus=\(status)")
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
