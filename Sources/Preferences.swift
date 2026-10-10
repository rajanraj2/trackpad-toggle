// Preferences.swift
// Thin UserDefaults wrapper. All persistence goes through this type.

import Foundation
import Carbon

/// Keys stored in UserDefaults.standard.
private enum PrefKey {
    static let hotKeyCode  = "hotKeyCode"
    static let hotKeyMods  = "hotKeyMods"
    static let launchAtLogin = "launchAtLogin"
}

/// Default shortcut: Control + Option + Command + T  (kVK_ANSI_T = 0x11)
private let defaultKeyCode: UInt32 = 0x11   // 't'
/// Carbon modifier flags: cmdKey | optionKey | controlKey
private let defaultMods: UInt32    = UInt32(cmdKey | optionKey | controlKey)

final class Preferences {
    static let shared = Preferences()
    private init() {}

    // MARK: – Hotkey

    var hotKeyCode: UInt32 {
        get {
            let v = UserDefaults.standard.integer(forKey: PrefKey.hotKeyCode)
            return v == 0 ? defaultKeyCode : UInt32(v)
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: PrefKey.hotKeyCode) }
    }

    var hotKeyModifiers: UInt32 {
        get {
            let v = UserDefaults.standard.integer(forKey: PrefKey.hotKeyMods)
            return v == 0 ? defaultMods : UInt32(v)
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: PrefKey.hotKeyMods) }
    }

    var hotKeyDescription: String {
        carbonModsToString(hotKeyModifiers) + carbonKeyCodeToString(hotKeyCode)
    }

    // MARK: – Reset

    func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: PrefKey.hotKeyCode)
        UserDefaults.standard.removeObject(forKey: PrefKey.hotKeyMods)
    }

    // MARK: – Helpers

    private func carbonModsToString(_ mods: UInt32) -> String {
        var s = ""
        if mods & UInt32(controlKey) != 0 { s += "⌃" }
        if mods & UInt32(optionKey)  != 0 { s += "⌥" }
        if mods & UInt32(shiftKey)   != 0 { s += "⇧" }
        if mods & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s
    }

    private func carbonKeyCodeToString(_ code: UInt32) -> String {
        // Covers the common printable keys used as hotkey triggers.
        let map: [UInt32: String] = [
            0x00:"A",0x01:"S",0x02:"D",0x03:"F",0x04:"H",0x05:"G",0x06:"Z",0x07:"X",
            0x08:"C",0x09:"V",0x0B:"B",0x0C:"Q",0x0D:"W",0x0E:"E",0x0F:"R",
            0x10:"Y",0x11:"T",0x12:"1",0x13:"2",0x14:"3",0x15:"4",0x16:"6",0x17:"5",
            0x18:"=",0x19:"9",0x1A:"7",0x1B:"-",0x1C:"8",0x1D:"0",0x1E:"]",0x1F:"O",
            0x20:"U",0x21:"[",0x22:"I",0x23:"P",0x25:"L",0x26:"J",0x27:"'",0x28:"K",
            0x29:";",0x2A:"\\",0x2B:",",0x2C:"/",0x2D:"N",0x2E:"M",0x2F:".",
            0x24:"↩",0x30:"⇥",0x31:"Space",0x33:"⌫",0x35:"⎋",
            0x7A:"F1",0x78:"F2",0x63:"F3",0x76:"F4",0x60:"F5",0x61:"F6",
            0x62:"F7",0x64:"F8",0x65:"F9",0x6D:"F10",0x67:"F11",0x6F:"F12",
        ]
        return map[code] ?? "0x\(String(code, radix: 16, uppercase: true))"
    }
}
