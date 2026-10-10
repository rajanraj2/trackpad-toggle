// main.swift
// Application entry point — bootstraps NSApplication with our AppDelegate.

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // accessory = no Dock icon (same as LSUIElement)
app.run()
