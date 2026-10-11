// TrackpadState.swift
// Explicit state model for the trackpad control lifecycle.

import Foundation

/// Specifies whether only the trackpad is locked or both the trackpad and keyboard are locked.
enum LockMode: Equatable {
    case trackpadOnly
    case fullLock // Trackpad & Keyboard
}

/// The canonical state of the built-in trackpad and keyboard input as tracked by this application.
enum TrackpadState: Equatable {
    /// Trackpad and keyboard are fully operational (initial/reset state).
    case enabled
    /// The event tap is installed with the specified lock mode.
    case disabled(mode: LockMode)
    /// An async operation is in progress (install/remove tap).
    case transitioning
    /// Accessibility and/or Input Monitoring permission is absent.
    /// The app cannot install an event tap without both.
    case permissionRequired
    /// The event tap could not be created or was invalidated by the OS.
    case failed(String)
    /// Should not occur on Apple Silicon MacBooks, included for completeness.
    case unsupported

    /// Convenience accessor for trackpad-only disabled mode.
    static var disabled: TrackpadState {
        .disabled(mode: .trackpadOnly)
    }

    var isOperational: Bool {
        switch self {
        case .enabled, .disabled: return true
        default: return false
        }
    }

    var isTrackpadDisabled: Bool {
        if case .disabled = self { return true }
        return false
    }

    var isKeyboardDisabled: Bool {
        if case .disabled(let mode) = self, mode == .fullLock { return true }
        return false
    }

    var displayTitle: String {
        switch self {
        case .enabled:            return "Trackpad: Enabled"
        case .disabled(let mode):
            switch mode {
            case .trackpadOnly:   return "Trackpad: Disabled"
            case .fullLock:       return "Trackpad & Keyboard: Locked"
            }
        case .transitioning:      return "Trackpad: Switching…"
        case .permissionRequired: return "Trackpad: ⚠️ Permission Required"
        case .failed(let msg):    return "Trackpad: Error — \(msg)"
        case .unsupported:        return "Trackpad: Unsupported"
        }
    }

    var menuBarSymbol: String {
        switch self {
        case .enabled:            return "hand.point.up.left.fill"
        case .disabled(let mode):
            switch mode {
            case .trackpadOnly:   return "hand.raised.slash.fill"
            case .fullLock:       return "lock.fill"
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
