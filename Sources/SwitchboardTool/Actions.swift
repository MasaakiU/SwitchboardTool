import AppKit

/// What a trigger (gesture, hot corner or key) does.
enum Action {
    case rightClick
    case leftClick
    case middleClick
    case key(code: CGKeyCode, flags: CGEventFlags)
    case openApp(String)

    var label: String {
        switch self {
        case .rightClick: return "right_click"
        case .leftClick: return "left_click"
        case .middleClick: return "middle_click"
        case .key(let code, let flags): return "key \(code) flags 0x\(String(flags.rawValue, radix: 16))"
        case .openApp(let app): return "open_app \(app)"
        }
    }

    /// Whether key auto-repeat should repeat the action (only for key sends, e.g. a Return replacement).
    var repeatsWhileHeld: Bool {
        if case .key = self { return true }
        return false
    }
}

/// Creates and posts synthetic clicks and keys. Posted events carry a mark so our own key tap ignores them.
enum Synth {
    static let magic: Int64 = 0x5342_5421   // "SBT!"

    static let source: CGEventSource? = {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.userData = magic
        return source
    }()

    static func isOurs(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == magic
    }

    static func perform(_ action: Action) {
        switch action {
        case .rightClick: click(.right)
        case .leftClick: click(.left)
        case .middleClick: click(.center)
        case .key(let code, let flags): key(code, flags: flags)
        case .openApp(let spec): openApp(spec)
        }
    }

    static func click(_ button: CGMouseButton) {
        guard let location = CGEvent(source: nil)?.location else {
            logger.error("cursor position unavailable")
            return
        }
        let types: (down: CGEventType, up: CGEventType)
        switch button {
        case .left: types = (.leftMouseDown, .leftMouseUp)
        case .right: types = (.rightMouseDown, .rightMouseUp)
        default: types = (.otherMouseDown, .otherMouseUp)
        }
        guard let down = CGEvent(mouseEventSource: source, mouseType: types.down, mouseCursorPosition: location, mouseButton: button),
              let up = CGEvent(mouseEventSource: source, mouseType: types.up, mouseCursorPosition: location, mouseButton: button)
        else { return }
        // Plain click: without this the event would inherit the modifier keys currently held down
        // (a key binding such as ctrl+L would otherwise produce a ctrl-click).
        down.flags = []
        up.flags = []
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static func key(_ code: CGKeyCode, flags: CGEventFlags) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static func openApp(_ spec: String) {
        guard let url = resolveApp(spec) else {
            logger.error("app not found: \(spec, privacy: .public)")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { logger.error("open failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// Accepts an absolute path, a ~ path, a bundle id (contains a dot) or an app name (searched in the standard folders).
    static func resolveApp(_ spec: String) -> URL? {
        if spec.hasPrefix("/") || spec.hasPrefix("~") {
            let path = (spec as NSString).expandingTildeInPath
            return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        if spec.contains("."), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: spec) {
            return url
        }
        let directories = ["/Applications", "/Applications/Utilities", NSHomeDirectory() + "/Applications",
                           "/System/Applications", "/System/Applications/Utilities", "/System/Library/CoreServices"]
        for directory in directories {
            let path = "\(directory)/\(spec).app"
            if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }
}
