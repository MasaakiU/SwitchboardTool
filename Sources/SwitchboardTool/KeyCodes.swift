import CoreGraphics
import Foundation

/// Key names ↔ virtual key codes (same values as Carbon's kVK_*). Letter keys follow the US physical layout.
enum KeyCodes {
    /// Ordered: the first name listed for a code is the one shown when a key is recorded.
    static let table: [(name: String, code: CGKeyCode)] = [
        ("return", 36), ("tab", 48), ("space", 49), ("delete", 51), ("escape", 53),
        ("left", 123), ("right", 124), ("down", 125), ("up", 126),
        ("home", 115), ("end", 119), ("pageup", 116), ("pagedown", 121), ("forwarddelete", 117), ("help", 114),
        ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7), ("c", 8), ("v", 9), ("b", 11),
        ("q", 12), ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17), ("1", 18), ("2", 19), ("3", 20), ("4", 21),
        ("6", 22), ("5", 23), ("=", 24), ("9", 25), ("7", 26), ("-", 27), ("8", 28), ("0", 29), ("]", 30), ("o", 31),
        ("u", 32), ("[", 33), ("i", 34), ("p", 35), ("l", 37), ("j", 38), ("'", 39), ("k", 40),
        (";", 41), ("\\", 42), (",", 43), ("/", 44), ("n", 45), ("m", 46), (".", 47), ("`", 50),
        ("f1", 122), ("f2", 120), ("f3", 99), ("f4", 118), ("f5", 96), ("f6", 97), ("f7", 98), ("f8", 100),
        ("f9", 101), ("f10", 109), ("f11", 103), ("f12", 111), ("f13", 105), ("f14", 107), ("f15", 113),
        ("f16", 106), ("f17", 64), ("f18", 79), ("f19", 80), ("f20", 90),
        ("keypad_decimal", 65), ("keypad_multiply", 67), ("keypad_plus", 69), ("keypad_clear", 71),
        ("keypad_divide", 75), ("keypad_enter", 76), ("keypad_minus", 78), ("keypad_equals", 81),
        ("keypad_0", 82), ("keypad_1", 83), ("keypad_2", 84), ("keypad_3", 85), ("keypad_4", 86),
        ("keypad_5", 87), ("keypad_6", 88), ("keypad_7", 89), ("keypad_8", 91), ("keypad_9", 92),
        // JIS keyboards
        ("yen", 93), ("underscore", 94), ("keypad_comma", 95), ("eisu", 102), ("kana", 104),
        // Special keys on Apple keyboards
        ("mission_control_key", 160), ("launchpad_key", 131),
    ]

    static let byName: [String: CGKeyCode] = Dictionary(table.map { ($0.name, $0.code) }, uniquingKeysWith: { first, _ in first })

    static let byCode: [CGKeyCode: String] = {
        var result: [CGKeyCode: String] = [:]
        for entry in table where result[entry.code] == nil { result[entry.code] = entry.name }
        return result
    }()

    static let relevantModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]

    /// Parses a combination such as "ctrl+alt+right". Returns nil when unreadable.
    static func parseCombo(_ text: String) -> (code: CGKeyCode, flags: CGEventFlags, mentionsFn: Bool)? {
        let parts = text.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard let keyName = parts.last, let code = byName[keyName] else { return nil }
        var flags: CGEventFlags = []
        var mentionsFn = false
        for modifier in parts.dropLast() {
            switch modifier {
            case "cmd", "command": flags.insert(.maskCommand)
            case "ctrl", "control": flags.insert(.maskControl)
            case "alt", "opt", "option": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            case "fn": flags.insert(.maskSecondaryFn); mentionsFn = true
            default: return nil
            }
        }
        return (code, flags, mentionsFn)
    }

    /// The text for a pressed key, e.g. "ctrl+alt+right". fn is left out: arrow and function keys set it on their own.
    static func comboText(keyCode: CGKeyCode, flags: CGEventFlags) -> String? {
        guard let name = byCode[keyCode] else { return nil }
        var parts: [String] = []
        if flags.contains(.maskCommand) { parts.append("cmd") }
        if flags.contains(.maskControl) { parts.append("ctrl") }
        if flags.contains(.maskAlternate) { parts.append("alt") }
        if flags.contains(.maskShift) { parts.append("shift") }
        parts.append(name)
        return parts.joined(separator: "+")
    }
}
