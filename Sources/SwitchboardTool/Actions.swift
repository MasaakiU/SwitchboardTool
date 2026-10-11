import AppKit

/// Keys that exist on the keyboard's media row; sent as system-defined events.
enum SystemKey: Int32 {
    case volumeUp = 0
    case volumeDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case playPause = 16
    case nextTrack = 17
    case previousTrack = 18
}

/// What a trigger (gesture, hot corner or key) does.
enum Action {
    case rightClick
    case leftClick
    case middleClick
    case key(code: CGKeyCode, flags: CGEventFlags)
    case openApp(String)
    case systemKey(SystemKey)

    var label: String {
        switch self {
        case .rightClick: return "right_click"
        case .leftClick: return "left_click"
        case .middleClick: return "middle_click"
        case .key(let code, let flags): return "key \(code) flags 0x\(String(flags.rawValue, radix: 16))"
        case .openApp(let app): return "open_app \(app)"
        case .systemKey(let key): return "system key \(key.rawValue)"
        }
    }

    /// Whether key auto-repeat should repeat the action (only for key sends, e.g. a Return replacement).
    var repeatsWhileHeld: Bool {
        if case .key = self { return true }
        return false
    }
}

/// The actions that have a plain name in config.json. Also the list the settings window offers.
enum NamedAction: String, CaseIterable, Identifiable {
    case rightClick = "right_click"
    case leftClick = "left_click"
    case middleClick = "middle_click"
    case spaceLeft = "space_left"
    case spaceRight = "space_right"
    case missionControl = "mission_control"
    case appExpose = "app_expose"
    case apps = "apps"
    case showDesktop = "show_desktop"
    case lockScreen = "lock_screen"
    case screenshotArea = "screenshot_area"
    case volumeUp = "volume_up"
    case volumeDown = "volume_down"
    case mute = "mute"
    case playPause = "play_pause"
    case nextTrack = "next_track"
    case previousTrack = "previous_track"
    case brightnessUp = "brightness_up"
    case brightnessDown = "brightness_down"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rightClick: return "Right click"
        case .leftClick: return "Left click"
        case .middleClick: return "Middle click"
        case .spaceLeft: return "Desktop to the left"
        case .spaceRight: return "Desktop to the right"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .apps: return "Apps (Launchpad key)"
        case .showDesktop: return "Show Desktop"
        case .lockScreen: return "Lock screen"
        case .screenshotArea: return "Screenshot of an area"
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .mute: return "Mute"
        case .playPause: return "Play / pause"
        case .nextTrack: return "Next track"
        case .previousTrack: return "Previous track"
        case .brightnessUp: return "Brightness up"
        case .brightnessDown: return "Brightness down"
        }
    }

    var action: Action {
        switch self {
        case .rightClick: return .rightClick
        case .leftClick: return .leftClick
        case .middleClick: return .middleClick
        case .spaceLeft: return .key(code: 123, flags: .maskControl)
        case .spaceRight: return .key(code: 124, flags: .maskControl)
        case .missionControl: return .key(code: 160, flags: [])
        case .appExpose: return .key(code: 125, flags: .maskControl)
        case .apps: return .key(code: 131, flags: [])
        case .showDesktop: return .key(code: 103, flags: [])
        case .lockScreen: return .key(code: 12, flags: [.maskControl, .maskCommand])
        case .screenshotArea: return .key(code: 21, flags: [.maskCommand, .maskShift])
        case .volumeUp: return .systemKey(.volumeUp)
        case .volumeDown: return .systemKey(.volumeDown)
        case .mute: return .systemKey(.mute)
        case .playPause: return .systemKey(.playPause)
        case .nextTrack: return .systemKey(.nextTrack)
        case .previousTrack: return .systemKey(.previousTrack)
        case .brightnessUp: return .systemKey(.brightnessUp)
        case .brightnessDown: return .systemKey(.brightnessDown)
        }
    }

    /// Older spellings still accepted in config.json.
    static func fromName(_ name: String) -> NamedAction? {
        switch name {
        case "desktop_left": return .spaceLeft
        case "desktop_right": return .spaceRight
        default: return NamedAction(rawValue: name)
        }
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
        case .systemKey(let key): systemKey(key)
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

    /// Media keys travel as "system defined" events (subtype 8); the key and the down/up state sit in data1.
    static func systemKey(_ key: SystemKey) {
        for isDown in [true, false] {
            let state: UInt = isDown ? 0xA00 : 0xB00
            let data1 = (Int(key.rawValue) << 16) | Int(state)
            guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                                 modifierFlags: NSEvent.ModifierFlags(rawValue: state),
                                                 timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
                                                 context: nil, subtype: 8, data1: data1, data2: -1)
            else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
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
