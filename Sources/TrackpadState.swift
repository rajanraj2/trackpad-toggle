// TrackpadState.swift
// Explicit state model for the trackpad control lifecycle.

import Foundation

/// The canonical state of the built-in trackpad as tracked by this application.
enum TrackpadState: Equatable {
    /// Trackpad is fully operational (initial/reset state).
    case enabled
    /// The event tap is installed and suppressing trackpad events.
    case disabled
    /// An async operation is in progress (install/remove tap).
    case transitioning
    /// Accessibility and/or Input Monitoring permission is absent.
    /// The app cannot install an event tap without both.
    case permissionRequired
    /// The event tap could not be created or was invalidated by the OS.
    case failed(String)
    /// Should not occur on Apple Silicon MacBooks, included for completeness.
    case unsupported

    var isOperational: Bool {
        switch self {
        case .enabled, .disabled: return true
        default: return false
        }
    }

    var displayTitle: String {
        switch self {
        case .enabled:            return "Trackpad: Enabled"
        case .disabled:           return "Trackpad: Disabled"
        case .transitioning:      return "Trackpad: Switching…"
        case .permissionRequired: return "Trackpad: ⚠️ Permission Required"
        case .failed(let msg):    return "Trackpad: Error — \(msg)"
        case .unsupported:        return "Trackpad: Unsupported"
        }
    }

    var menuBarSymbol: String {
        switch self {
        case .enabled:            return "hand.point.up.left.fill"
        case .disabled:           return "hand.raised.slash.fill"
        case .transitioning:      return "arrow.triangle.2.circlepath"
        case .permissionRequired: return "exclamationmark.triangle.fill"
        case .failed:             return "xmark.circle.fill"
        case .unsupported:        return "questionmark.circle.fill"
        }
    }

    static func == (lhs: TrackpadState, rhs: TrackpadState) -> Bool {
        switch (lhs, rhs) {
        case (.enabled, .enabled),
             (.disabled, .disabled),
             (.transitioning, .transitioning),
             (.permissionRequired, .permissionRequired),
             (.unsupported, .unsupported):
            return true
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}
