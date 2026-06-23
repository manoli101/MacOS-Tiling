import Foundation
import AppKit

// MARK: - Shortcut model

struct Shortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt   // NSEvent.ModifierFlags rawValue (only command/option/control/shift bits)

    static let defaults: [String: Shortcut] = [
        "left":  Shortcut(keyCode: 123, modifiers: NSEvent.ModifierFlags.option.rawValue),
        "right": Shortcut(keyCode: 124, modifiers: NSEvent.ModifierFlags.option.rawValue),
        "up":    Shortcut(keyCode: 126, modifiers: NSEvent.ModifierFlags.option.rawValue),
        "down":  Shortcut(keyCode: 125, modifiers: NSEvent.ModifierFlags.option.rawValue),
        "undo":  Shortcut(keyCode: 6,   modifiers: NSEvent.ModifierFlags.option.rawValue), // ⌥Z
    ]

    var displayString: String {
        var s = ""
        let f = NSEvent.ModifierFlags(rawValue: modifiers)
        if f.contains(.control)  { s += "⌃" }
        if f.contains(.option)   { s += "⌥" }
        if f.contains(.shift)    { s += "⇧" }
        if f.contains(.command)  { s += "⌘" }
        s += keyName
        return s
    }

    private var keyName: String {
        switch keyCode {
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 0:   return "A"
        case 1:   return "S"
        case 2:   return "D"
        case 3:   return "F"
        case 4:   return "H"
        case 5:   return "G"
        case 6:   return "Z"
        case 7:   return "X"
        case 8:   return "C"
        case 9:   return "V"
        case 11:  return "B"
        case 12:  return "Q"
        case 13:  return "W"
        case 14:  return "E"
        case 15:  return "R"
        case 16:  return "Y"
        case 17:  return "T"
        case 31:  return "O"
        case 32:  return "U"
        case 34:  return "I"
        case 35:  return "P"
        case 37:  return "L"
        case 38:  return "J"
        case 40:  return "K"
        case 45:  return "N"
        case 46:  return "M"
        default:  return "[\(keyCode)]"
        }
    }
}

// MARK: - Settings

@MainActor
enum Settings {

    // ── Window Gap ────────────────────────────────────────────────────
    static var windowGap: Int {
        get { UserDefaults.standard.integer(forKey: "windowGap") }
        set { UserDefaults.standard.set(newValue, forKey: "windowGap"); notify() }
    }

    // ── Status indicators in menu ─────────────────────────────────────
    static var showStatusIndicators: Bool {
        get { UserDefaults.standard.object(forKey: "showStatusIndicators") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showStatusIndicators"); notify() }
    }

    // ── Layout icon in menu bar ───────────────────────────────────────
    static var showLayoutInStatusIcon: Bool {
        get { UserDefaults.standard.object(forKey: "showLayoutInStatusIcon") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showLayoutInStatusIcon"); notify() }
    }

    // ── Feature toggles ───────────────────────────────────────────────
    static var enableThirds: Bool {
        get { UserDefaults.standard.object(forKey: "enableThirds") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "enableThirds"); notify() }
    }

    static var enableUndo: Bool {
        get { UserDefaults.standard.object(forKey: "enableUndo") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "enableUndo"); notify() }
    }

    static var enableSnapOverlay: Bool {
        get { UserDefaults.standard.object(forKey: "enableSnapOverlay") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "enableSnapOverlay"); notify() }
    }

    static var enableCustomShortcuts: Bool {
        get { UserDefaults.standard.object(forKey: "enableCustomShortcuts") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "enableCustomShortcuts"); notify() }
    }

    // ── Shortcuts ─────────────────────────────────────────────────────
    static func shortcut(for action: String) -> Shortcut {
        guard enableCustomShortcuts,
              let data = UserDefaults.standard.data(forKey: "shortcut_\(action)"),
              let s = try? JSONDecoder().decode(Shortcut.self, from: data) else {
            return Shortcut.defaults[action] ?? Shortcut(keyCode: 0, modifiers: 0)
        }
        return s
    }

    static func setShortcut(_ s: Shortcut, for action: String) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        UserDefaults.standard.set(data, forKey: "shortcut_\(action)")
        notify()
    }

    static func resetShortcuts() {
        for action in Shortcut.defaults.keys {
            UserDefaults.standard.removeObject(forKey: "shortcut_\(action)")
        }
    }

    // ── Reset all ─────────────────────────────────────────────────────
    static func reset() {
        let keys = ["windowGap", "showStatusIndicators", "showLayoutInStatusIcon",
                    "enableThirds", "enableUndo", "enableSnapOverlay", "enableCustomShortcuts"]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        resetShortcuts()
        notify()
    }

    private static func notify() {
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
}

extension Notification.Name {
    static let settingsChanged = Notification.Name("TylerSettingsChanged")
}
