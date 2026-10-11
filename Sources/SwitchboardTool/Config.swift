import Foundation

struct Tuning {
    var tapMaxDuration: Double = 0.20
    var tapMaxMove: Float = 0.03
    var cornerDwell: Double = 0.20
    var cornerTolerance: CGFloat = 2
}

struct Config {
    var gestures: [Int: Action] = [:]            // finger count → action (tap)
    var corners: [Corner: CornerBinding] = [:]
    var keys: [KeyTrigger: Action] = [:]
    var tuning = Tuning()
}

/// Where the config file lives. Created with defaults when missing.
final class ConfigStore {
    let directory: URL
    let url: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = base.appendingPathComponent("Switchboard Tool", isDirectory: true)
        url = directory.appendingPathComponent("config.json")
    }

    func ensureExists() {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try ConfigParser.defaultText.write(to: url, atomically: true, encoding: .utf8)
            logger.info("wrote default config to \(self.url.path, privacy: .public)")
        } catch {
            logger.error("could not write default config: \(error.localizedDescription, privacy: .public)")
        }
    }

    func load() -> (Config, [String]) {
        guard let data = try? Data(contentsOf: url) else { return (Config(), ["The config file could not be read: \(url.path)"]) }
        return ConfigParser.parse(data)
    }
}

enum ConfigParser {
    static let defaultText = """
    {
      "gestures": {
        "two_finger_tap": "right_click"
      },
      "hot_corners": {
      },
      "keys": {
      },
      "tuning": {
        "tap_max_ms": 200,
        "tap_max_move": 0.03,
        "corner_dwell_ms": 200
      }
    }

    """

    static let gestureNames: [String: Int] = [
        "two_finger_tap": 2, "three_finger_tap": 3, "four_finger_tap": 4, "five_finger_tap": 5,
    ]

    static func parse(_ data: Data) -> (Config, [String]) {
        var errors: [String] = []
        var config = Config()
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            return (config, ["Not valid JSON: \(error.localizedDescription)"])
        }
        guard let root = object as? [String: Any] else { return (config, ["The top level must be an object { }"]) }
        for key in root.keys where !["gestures", "hot_corners", "keys", "tuning"].contains(key) {
            errors.append("Unknown section: \(key)")
        }

        if let tuning = root["tuning"] as? [String: Any] {
            for (key, value) in tuning {
                guard let number = (value as? NSNumber)?.doubleValue else { errors.append("tuning.\(key): expected a number"); continue }
                switch key {
                case "tap_max_ms": config.tuning.tapMaxDuration = number / 1000
                case "tap_max_move": config.tuning.tapMaxMove = Float(number)
                case "corner_dwell_ms": config.tuning.cornerDwell = number / 1000
                case "corner_tolerance_px": config.tuning.cornerTolerance = CGFloat(number)
                default: errors.append("tuning: unknown key \(key)")
                }
            }
        }

        if let gestures = root["gestures"] as? [String: Any] {
            for (name, value) in gestures {
                guard let fingers = gestureNames[name] else { errors.append("gestures: unknown gesture \(name)"); continue }
                if let action = parseAction(value, at: "gestures.\(name)", errors: &errors) { config.gestures[fingers] = action }
            }
        }

        if let corners = root["hot_corners"] as? [String: Any] {
            for (name, value) in corners {
                guard let corner = Corner(rawValue: name) else { errors.append("hot_corners: unknown corner \(name)"); continue }
                var dwell: Double?
                var raw: Any = value
                if var dict = value as? [String: Any] {
                    if let ms = (dict["dwell_ms"] as? NSNumber)?.doubleValue { dwell = ms / 1000 }
                    dict.removeValue(forKey: "dwell_ms")
                    raw = dict
                }
                if let action = parseAction(raw, at: "hot_corners.\(name)", errors: &errors) {
                    config.corners[corner] = CornerBinding(action: action, dwell: dwell)
                }
            }
        }

        if let keys = root["keys"] as? [String: Any] {
            for (combo, value) in keys {
                guard let parsed = KeyCodes.parseCombo(combo) else { errors.append("keys: unreadable key combination \"\(combo)\""); continue }
                let trigger = KeyTrigger(code: parsed.code, flags: parsed.flags, caresAboutFn: parsed.mentionsFn)
                if let action = parseAction(value, at: "keys.\(combo)", errors: &errors) { config.keys[trigger] = action }
            }
        }
        return (config, errors)
    }

    static func parseAction(_ raw: Any, at path: String, errors: inout [String]) -> Action? {
        if let name = raw as? String {
            switch name {
            case "right_click": return .rightClick
            case "left_click": return .leftClick
            case "middle_click": return .middleClick
            case "space_left", "desktop_left": return .key(code: 123, flags: .maskControl)
            case "space_right", "desktop_right": return .key(code: 124, flags: .maskControl)
            case "mission_control": return .key(code: 160, flags: [])
            case "apps": return .key(code: 131, flags: [])
            case "show_desktop": return .key(code: 103, flags: [])
            default:
                if let combo = KeyCodes.parseCombo(name) { return .key(code: combo.code, flags: combo.flags) }
                errors.append("\(path): unknown action \"\(name)\"")
                return nil
            }
        }
        if let dict = raw as? [String: Any] {
            if let app = dict["open_app"] as? String { return .openApp(app) }
            if let combo = dict["key"] as? String {
                if let parsed = KeyCodes.parseCombo(combo) { return .key(code: parsed.code, flags: parsed.flags) }
                errors.append("\(path): unreadable key combination \"\(combo)\"")
                return nil
            }
            errors.append("\(path): expected open_app or key")
            return nil
        }
        errors.append("\(path): expected a string or an object { }")
        return nil
    }
}
