import AppKit

/// A key combination. fn is only compared when the trigger mentions it (arrow keys and others set fn on their own).
struct KeyTrigger: Hashable {
    let keyCode: CGKeyCode
    let modifiers: UInt64
    let caresAboutFn: Bool

    init(code: CGKeyCode, flags: CGEventFlags, caresAboutFn: Bool) {
        keyCode = code
        self.caresAboutFn = caresAboutFn
        modifiers = flags.intersection(KeyBindingTap.relevantMask(caresAboutFn: caresAboutFn)).rawValue
    }

    /// The combination as written in config.json, e.g. "ctrl+alt+right".
    var name: String {
        let flags = CGEventFlags(rawValue: modifiers)
        let text = KeyCodes.comboText(keyCode: keyCode, flags: flags) ?? "key \(keyCode)"
        return caresAboutFn && flags.contains(.maskSecondaryFn) ? "fn+" + text : text
    }
}

/// Intercepts key events; a registered combination is swallowed and performs its action. Needs the Accessibility permission.
final class KeyBindingTap {
    static let modifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    static func relevantMask(caresAboutFn: Bool) -> CGEventFlags {
        caresAboutFn ? modifierMask.union(.maskSecondaryFn) : modifierMask
    }

    var bindings: [KeyTrigger: Action] = [:]
    var onAction: ((Action) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var swallowedKeyUps = Set<CGKeyCode>()
    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        if tap != nil { return true }
        let mask: CGEventMask = (1 << CGEventMask(CGEventType.keyDown.rawValue)) | (1 << CGEventMask(CGEventType.keyUp.rawValue))
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: keyTapCallback, userInfo: refcon)
        else {
            logger.error("keyboard event tap could not be created")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        logger.notice("keyboard event tap started")
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            // Dropping the port alone leaves the tap registered (disabled) with the window server.
            CFMachPortInvalidate(tap)
            logger.notice("keyboard event tap stopped")
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        swallowedKeyUps.removeAll()
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let why = type == .tapDisabledByTimeout ? "timeout" : "user input"
            logger.notice("keyboard event tap was disabled by \(why, privacy: .public); enabling it again")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown || type == .keyUp, !Synth.isOurs(event) else { return Unmanaged.passUnretained(event) }
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp {
            return swallowedKeyUps.remove(keyCode) != nil ? nil : Unmanaged.passUnretained(event)
        }
        for (trigger, action) in bindings where trigger.keyCode == keyCode {
            let mask = Self.relevantMask(caresAboutFn: trigger.caresAboutFn)
            guard event.flags.intersection(mask).rawValue == trigger.modifiers else { continue }
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            swallowedKeyUps.insert(keyCode)
            if !isRepeat { logger.notice("key \(trigger.name, privacy: .public) -> \(action.label, privacy: .public)") }
            if !isRepeat || action.repeatsWhileHeld {
                DispatchQueue.main.async { [action] in self.onAction?(action) }
            }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}

private func keyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                            refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<KeyBindingTap>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
}
