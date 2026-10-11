import Combine
import Foundation

/// An action as written in config.json, kept in its written form so the settings window can edit it.
enum ActionSpec: Equatable {
    case named(NamedAction)
    case key(String)
    case openApp(String)

    static func from(_ raw: Any) -> ActionSpec? {
        if let text = raw as? String {
            if let named = NamedAction.fromName(text) { return .named(named) }
            if KeyCodes.parseCombo(text) != nil { return .key(text) }
            return nil
        }
        if let dict = raw as? [String: Any] {
            if let name = dict["action"] as? String { return from(name) }
            if let app = dict["open_app"] as? String { return .openApp(app) }
            if let combo = dict["key"] as? String { return .key(combo) }
        }
        return nil
    }

    var json: Any {
        switch self {
        case .named(let named): return named.rawValue
        case .key(let combo): return ["key": combo]
        case .openApp(let app): return ["open_app": app]
        }
    }
}

struct GestureRow: Identifiable {
    let id: UUID
    var gesture: TrackpadGesture
    var action: ActionSpec
}

struct KeyRow: Identifiable {
    let id: UUID
    var combo: String
    var action: ActionSpec
}

struct CornerRow {
    var action: ActionSpec?
    var dwellMs: Double?
}

struct TuningValues: Equatable {
    var tapMaxMs: Double = 200
    var tapMaxMove: Double = 0.03
    var swipeMinDistance: Double = 0.20
    var swipeMaxMs: Double = 600
    var edgeBand: Double = 0.08
    var cornerDwellMs: Double = 200
    var cornerTolerancePx: Double = 2
}

/// The settings window's model: the config file as rows. Every edit is written back a moment later.
final class ConfigDocument: ObservableObject {
    @Published var gestures: [GestureRow] = []
    @Published var corners: [Corner: CornerRow] = [:]
    @Published var keys: [KeyRow] = []
    @Published var tuning = TuningValues()
    /// Entries the window cannot show; they are dropped from the file on the next save.
    @Published private(set) var skipped: [String] = []

    var onSaved: (() -> Void)?
    var fileURL: URL { store.url }

    private let store: ConfigStore
    private var cancellables = Set<AnyCancellable>()
    private var pendingSave: DispatchWorkItem?
    private var loading = false
    /// The file as this model would write it, from the last load or save. Saving is skipped while nothing changed
    /// (SwiftUI controls write their value back on appearance, which must not rewrite the file).
    private var lastText = ""

    init(store: ConfigStore) {
        self.store = store
        reload()
        let edits = Publishers.Merge4(
            $gestures.map { _ in () }, $corners.map { _ in () }, $keys.map { _ in () }, $tuning.map { _ in () })
        // Each @Published publisher replays its current value when subscribed; skip those four so that
        // merely opening the window does not rewrite the file.
        edits.dropFirst(4).sink { [weak self] _ in self?.scheduleSave() }.store(in: &cancellables)
    }

    func reload() {
        loading = true
        defer { loading = false }
        gestures = []
        corners = [:]
        keys = []
        tuning = TuningValues()
        skipped = []
        guard let text = store.readText(), let data = text.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }

        if let section = root["gestures"] as? [String: Any] {
            for name in section.keys.sorted() {
                if let gesture = TrackpadGesture(name: name), let action = ActionSpec.from(section[name]!) {
                    gestures.append(GestureRow(id: UUID(), gesture: gesture, action: action))
                } else {
                    skipped.append("gestures.\(name)")
                }
            }
        }
        if let section = root["hot_corners"] as? [String: Any] {
            for (name, value) in section {
                guard let corner = Corner(rawValue: name) else { skipped.append("hot_corners.\(name)"); continue }
                var dwell: Double?
                var raw: Any = value
                if var dict = value as? [String: Any] {
                    dwell = (dict["dwell_ms"] as? NSNumber)?.doubleValue
                    dict.removeValue(forKey: "dwell_ms")
                    raw = dict
                }
                if let action = ActionSpec.from(raw) {
                    corners[corner] = CornerRow(action: action, dwellMs: dwell)
                } else {
                    skipped.append("hot_corners.\(name)")
                }
            }
        }
        if let section = root["keys"] as? [String: Any] {
            for combo in section.keys.sorted() {
                if let action = ActionSpec.from(section[combo]!) {
                    keys.append(KeyRow(id: UUID(), combo: combo, action: action))
                } else {
                    skipped.append("keys.\(combo)")
                }
            }
        }
        if let section = root["tuning"] as? [String: Any] {
            func number(_ key: String) -> Double? { (section[key] as? NSNumber)?.doubleValue }
            if let v = number("tap_max_ms") { tuning.tapMaxMs = v }
            if let v = number("tap_max_move") { tuning.tapMaxMove = v }
            if let v = number("swipe_min_distance") { tuning.swipeMinDistance = v }
            if let v = number("swipe_max_ms") { tuning.swipeMaxMs = v }
            if let v = number("edge_band") { tuning.edgeBand = v }
            if let v = number("corner_dwell_ms") { tuning.cornerDwellMs = v }
            if let v = number("corner_tolerance_px") { tuning.cornerTolerancePx = v }
        }
        lastText = jsonText()
    }

    private func scheduleSave() {
        guard !loading else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func save() {
        let text = jsonText()
        guard text != lastText else { return }
        do {
            try store.save(text: text)
            lastText = text
            logger.info("config saved from the settings window")
            onSaved?()
        } catch {
            logger.error("could not save config: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The file text, in a fixed order with two-space indentation.
    func jsonText() -> String {
        func quoted(_ text: String) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed, .withoutEscapingSlashes])) ?? Data()
            return String(data: data, encoding: .utf8) ?? "\"\""
        }
        func value(_ json: Any) -> String {
            if let text = json as? String { return quoted(text) }
            if let dict = json as? [String: Any] {
                let inner = dict.keys.sorted().map { "\(quoted($0)): \(value(dict[$0]!))" }.joined(separator: ", ")
                return "{ \(inner) }"
            }
            if let number = json as? NSNumber { return number.stringValue }
            return "null"
        }
        func numberText(_ number: Double) -> String {
            number == number.rounded() ? String(Int(number)) : String(format: "%g", number)
        }
        var lines: [String] = ["{"]
        lines.append("  \"gestures\": {")
        lines.append(gestures.map { "    \(quoted($0.gesture.name)): \(value($0.action.json))" }.joined(separator: ",\n"))
        lines.append("  },")
        lines.append("  \"hot_corners\": {")
        var cornerLines: [String] = []
        for corner in Corner.allCases {
            guard let row = corners[corner], let action = row.action else { continue }
            var json = action.json
            if let dwell = row.dwellMs {
                var dict = (json as? [String: Any]) ?? ["key": (json as? String) ?? ""]
                if let named = json as? String { dict = ["action": named] }
                dict["dwell_ms"] = NSNumber(value: dwell)
                json = dict
            }
            cornerLines.append("    \(quoted(corner.rawValue)): \(value(json))")
        }
        lines.append(cornerLines.joined(separator: ",\n"))
        lines.append("  },")
        lines.append("  \"keys\": {")
        lines.append(keys.filter { !$0.combo.isEmpty }.map { "    \(quoted($0.combo)): \(value($0.action.json))" }.joined(separator: ",\n"))
        lines.append("  },")
        lines.append("  \"tuning\": {")
        lines.append([
            "    \"tap_max_ms\": \(numberText(tuning.tapMaxMs))",
            "    \"tap_max_move\": \(numberText(tuning.tapMaxMove))",
            "    \"swipe_min_distance\": \(numberText(tuning.swipeMinDistance))",
            "    \"swipe_max_ms\": \(numberText(tuning.swipeMaxMs))",
            "    \"edge_band\": \(numberText(tuning.edgeBand))",
            "    \"corner_dwell_ms\": \(numberText(tuning.cornerDwellMs))",
            "    \"corner_tolerance_px\": \(numberText(tuning.cornerTolerancePx))",
        ].joined(separator: ",\n"))
        lines.append("  }")
        lines.append("}")
        return lines.filter { !$0.isEmpty }.joined(separator: "\n") + "\n"
    }
}
