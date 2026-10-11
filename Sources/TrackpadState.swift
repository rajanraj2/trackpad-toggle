// TrackpadState.swift
// Explicit state model for the trackpad control lifecycle.

import Foundation

/// Specifies whether only the trackpad is locked or both the trackpad and keyboard are locked.
/// Tracks which input components are currently suppressed.
struct LockState: Equatable {
    var trackpadLocked: Bool = false
    var keyboardLocked: Bool = false

    var anyLocked: Bool { trackpadLocked || keyboardLocked }
}

/// The canonical state of the built-in trackpad and keyboard input.
enum TrackpadState: Equatable {
    case enabled
    case disabled(locks: LockState)
    case transitioning
    case permissionRequired
    case failed(String)
    case unsupported

    /// Convenience for trackpad-only disable.
    static var disabled: TrackpadState {
        .disabled(locks: LockState(trackpadLocked: true, keyboardLocked: false))
    }

    var isOperational: Bool {
        switch self {
        case .enabled, .disabled: return true
        default: return false
        }
    }

    var isTrackpadDisabled: Bool {
        if case .disabled(let locks) = self { return locks.trackpadLocked }
        return false
    }

    var isKeyboardDisabled: Bool {
        if case .disabled(let locks) = self, locks.keyboardLocked { return true }
        return false
    }

    var displayTitle: String {
        switch self {
        case .enabled:            return "Trackpad: Enabled"
        case .disabled(let locks):
            if locks.trackpadLocked && locks.keyboardLocked {
                return "Trackpad & Keyboard: Locked"
            } else if locks.trackpadLocked {
                return "Trackpad: Disabled"
            } else {
                return "Keyboard: Locked"
            }
        case .transitioning:      return "Trackpad: Switching…"
        case .permissionRequired: return "Trackpad: ⚠️ Permission Required"
        case .failed(let msg):    return "Trackpad: Error — \(msg)"
        case .unsupported:       return "Trackpad: Unsupported"
        }
    }

    var menuBarSymbol: String {
        switch self {
        case .enabled:            return "hand.point.up.left.fill"
        case .disabled(let locks):
            if locks.trackpadLocked && locks.keyboardLocked {
                return "lock.fill"
            } else if locks.trackpadLocked {
                return "hand.raised.slash.fill"
            } else {
                return "keyboard.slash"
            }
        case .transitioning:      return "arrow.triangle.2.circlepath"
        case .permissionRequired: return "exclamationmark.triangle.fill"
        case .failed:             return "xmark.circle.fill"
        case .unsupported:        return "questionmark.circle.fill"
        }
    }

    static func == (lhs: TrackpadState, rhs: TrackpadState) -> Bool {
        switch (lhs, rhs) {
        case (.enabled, .enabled),
             (.transitioning, .transitioning),
             (.permissionRequired, .permissionRequired),
             (.unsupported, .unsupported):
            return true
        case (.disabled(let a), .disabled(let b)):
            return a == b
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

