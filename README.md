# Trackpad Toggle

A lightweight macOS menu-bar utility that lets you disable and re-enable the built-in trackpad with a single configurable keyboard shortcut.

## Requirements

- macOS 14 (Sonoma) or later (tested on macOS 27.0.1)
- MacBook with built-in trackpad (Apple Silicon confirmed)
- Xcode Command Line Tools (`xcode-select --install`)

## Installation & Starting Without Terminal

### Option A: Spotlight, Launchpad, or Finder (Recommended)
1. In Finder, double-click **`Install.command`** in the project folder (or run `bash build.sh --install`).
2. This compiles and places **Trackpad Toggle** directly into your **Applications** folder.
3. From now on, launch it just like any native Mac app:
   - **Spotlight**: Press **⌘ + Space**, type `Trackpad Toggle`, and hit Enter.
   - **Launchpad**: Click the Trackpad Toggle icon.
   - **Finder**: Open `/Applications` and double-click `TrackpadToggle.app`.

### Option B: Automatic Startup (Zero Clicks Required)
Once opened for the first time:
1. Click the menu-bar icon → check **Launch at Login** (or toggle it in Settings).
2. **You never have to start the app manually again.** It starts automatically in the background every time you turn on or log into your Mac.

### Option C: Shareable Disk Image (DMG) for Other Users
If you want to share the app with users who don't want to touch developer tools:
```bash
bash build.sh --dmg
```
This generates **`build/TrackpadToggle.dmg`**. Any user can double-click the `.dmg` in Finder and drag `TrackpadToggle.app` to their Applications folder without using Terminal at all.
## First Launch & Permissions

macOS requires two TCC permissions before the event tap can suppress trackpad input.

| Permission | Where | Why |
|---|---|---|
| **Accessibility** | System Settings → Privacy & Security → Accessibility | Install a system-wide CGEventTap |
| **Input Monitoring** | System Settings → Privacy & Security → Input Monitoring | Allow the tap to *suppress* (not just observe) events |

Without both, the app runs but cannot block trackpad events. A warning banner appears in the menu.

**Steps after first launch:**

1. macOS shows the Accessibility prompt → click *Open System Settings* → toggle the switch.
2. Try toggling the trackpad — if a second alert appears mentioning Input Monitoring, open that panel too and enable the app.
3. Quit and relaunch. Both permissions persist across restarts.

## Usage

| Action | How |
|---|---|
| Toggle trackpad on/off | Press **⌃⌥⌘T** (default) or click the menu-bar icon |
| Change shortcut key | Click menu bar → **Change Shortcut…** or open **Settings…** |
| Enable/disable startup at login | Click menu bar → **Launch at Login** (checkmark toggle) or in **Settings…** |
| Open Settings | Click menu bar → Settings… or press **⌘,** |
| Quit | Click menu bar → Quit, or press **⌘Q** in Settings |

### Setting & Updating Shortcut Key

You can customize the global toggle shortcut at any time:

1. Click the menu-bar icon and select **Change Shortcut…** (or open **Settings…**).
2. Click **Change Shortcut…** to enter recording mode.
3. Press your desired key combination with modifiers (e.g. `⌃⌥T`, `⌥⌘T`, `⌃⌘T`, or `F6`).
4. Press **Esc** to cancel without making changes.
5. Alternatively, click any of the **Quick Presets** (`⌃⌥⌘T`, `⌃⌥T`, `⌥⌘T`, `⌃⌘T`, `F6`) for 1-click switching.
6. If another app conflicts with your shortcut, the app warns you inline with an error badge.

The shortcut uses **Carbon `RegisterEventHotKey`**, so it works globally regardless of focused window, requires no Accessibility permission, and continues to fire when the trackpad is disabled.

### Automatic Startup at Login

You can have Trackpad Toggle start automatically when you log in:

- **From the Menu Bar**: Click the menu-bar icon → toggle **Launch at Login** (shows a checkmark `✓` when enabled).
- **From Settings**: Toggle **Start automatically at login**.

This uses the modern macOS `SMAppService.mainApp` Login Items API with a standard `~/Library/LaunchAgents` fallback, ensuring it starts seamlessly as a background menu-bar accessory.

## Running Automated Tests

```bash
swift Tests/TrackpadToggleTests.swift
```

No permissions or hardware required. Tests cover state transitions, permission-failure paths, shortcut updates, presets, and startup/login persistence. Expected output ends with `PASS` (20/20 tests passing).

## Architecture

```
Sources/
├── main.swift                     — NSApplication bootstrap
├── AppDelegate.swift              — coordinator, sleep/wake, permission alerts, menu actions
├── TrackpadState.swift            — explicit state enum (enabled/disabled/transitioning/…)
├── TrackpadController.swift       — protocol + CGEventTapController implementation
├── HotKeyManager.swift            — Carbon RegisterEventHotKey engine + conflict detection
├── LaunchAtLoginManager.swift     — SMAppService & LaunchAgent startup management
├── PermissionsManager.swift       — Accessibility + Input Monitoring TCC checks
├── Preferences.swift              — UserDefaults wrapper, shortcut presets & persistence
├── MenuBarController.swift        — NSStatusItem + dynamic NSMenu with quick toggles
└── SettingsWindowController.swift — SwiftUI settings, shortcut recorder & startup controls
```

## Trackpad Control Mechanism

### What was investigated

| Mechanism | Outcome |
|---|---|
| `IOHIDManager` seize (`kIOHIDOptionsTypeSeizeDevice`) | `kIOReturnNotPrivileged` — requires root. Eliminated. |
| `MultitouchSupport.framework` `MTDeviceStop` | Per-process stream only; WindowServer unaffected. Eliminated. |
| `defaults write com.apple.AppleMultitouchTrackpad USBMouseStopsTrackpad 1` | Only works when a USB mouse is present; needs re-login. Not suitable. |
| **CGEventTap** (`kCGHIDEventTap`, `kCGHeadInsertEventTap`, `kCGEventTapOptionDefault`) | ✅ **Selected.** Intercepts synthesised HID pointer events before delivery to any app. Requires Accessibility + Input Monitoring. |

### What CGEventTap suppresses

| Input | Suppressed? |
|---|---|
| Pointer movement | ✅ Yes |
| Physical click (left/right) | ✅ Yes |
| Tap-to-click | ✅ Yes (synthesised as a left-click at HID layer) |
| Two-finger scroll | ✅ Yes |
| Click-and-drag | ✅ Yes |
| System multitouch gestures (Mission Control, Launchpad swipe, Exposé) | ⚠️ **No** — these are processed inside WindowServer from raw MultitouchSupport data *before* CGEventTap sees them |

### Device discrimination

CGEventTap does not expose a stable per-device hardware identifier in a public API.  
Two heuristics are used to pass external-mouse events through:

- **Scroll events** — `kCGScrollWheelEventIsContinuous == 0` → discrete scroll wheel (external mouse) → passed through.
- **Pointer events** — `kCGMouseEventSubtype == 0` **and** `kCGMouseEventPressure == 0` → likely external mouse → passed through.

External USB/Bluetooth mice should continue to function normally for clicks and scrolling. Pointer movement from external mice is *best-effort* — the heuristic is reliable on tested hardware but not guaranteed across all third-party devices.

### Shortcut engine

The global shortcut uses **Carbon `RegisterEventHotKey`**, which operates at kernel level and requires **no TCC permissions**. This is the critical safety design: the recovery shortcut fires even if all TCC permissions are revoked and the trackpad is disabled.

## Recovery

If the trackpad is disabled and you cannot interact with the UI:

1. **Press the registered shortcut** (default **⌃⌥⌘T**) to toggle it back on.
2. **Quit the app** — the event tap is removed on exit, re-enabling the trackpad:
   - Via keyboard shortcut registered in Settings, or
   - Open Terminal and run: `killall TrackpadToggle`
3. **Reboot** — the trackpad always returns after a restart.

The app **never** affects the keyboard or external pointing devices independently.

## Manual Verification Checklist

Run these after building and launching the app:

- [ ] Menu bar icon appears (hand icon).
- [ ] Default state shows "Trackpad: Enabled".
- [ ] ⌃⌥⌘T disables — cursor stops responding to trackpad.
- [ ] Tap-to-click does not fire while disabled.
- [ ] Two-finger scroll does not fire while disabled.
- [ ] Keyboard input works normally while disabled.
- [ ] ⌃⌥⌘T re-enables — trackpad works immediately.
- [ ] Sleep → wake → state preserved correctly.
- [ ] Quitting the app always re-enables the trackpad.
- [ ] Settings → shortcut recorder → new combo takes effect without relaunch.
- [ ] Revoking Accessibility → permission warning appears in menu.

## Limitations

1. **System gestures not blocked** — Mission Control, Exposé, Launchpad swipes bypass CGEventTap.
2. **No sandbox** — `CGEventTap` in suppression mode is incompatible with the App Sandbox entitlement. The app must run unsandboxed (standard for local developer tools).
3. **No notarisation** — the build script uses an ad-hoc signature. Gatekeeper will warn on first open; right-click → Open to bypass.
4. **External mouse discrimination is heuristic** — tested on Apple-standard hardware; exotic mice may behave differently.

## Troubleshooting

**App doesn't appear in the menu bar**  
Check that `LSUIElement = true` is in Info.plist and the binary is inside a valid `.app` bundle structure.

**Trackpad still moves cursor after disabling**  
Accessibility or Input Monitoring permission is missing. Open Settings → check the Permissions section.

**Shortcut doesn't fire**  
Another app has registered the same combination (Carbon hot keys are system-exclusive). Change the shortcut in Settings.

**App crashes on launch**  
Run from Terminal: `./build/TrackpadToggle.app/Contents/MacOS/TrackpadToggle` to see the error output.
