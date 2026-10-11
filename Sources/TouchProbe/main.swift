// TouchProbe: test tool.
//   touch      receive raw finger data and log it; two-finger taps are detected and recorded. Needs no permission.
//   click      post a right click at the cursor after 3 seconds. Needs the Accessibility permission.
//   tap2click  both of the above: a two-finger tap posts a right click.
// Usage: TouchProbe [touch|click|tap2click] [--seconds N] [--log PATH]
import Foundation
import AppKit
import IOKit.hid
import CMultitouch

// ---- arguments ----------------------------------------------------------------
var mode = "touch"
var seconds: Double = 20
var logPath: String? = nil
var askInputMonitoring = false
var rest = Array(CommandLine.arguments.dropFirst())
while !rest.isEmpty {
    let a = rest.removeFirst()
    switch a {
    case "touch", "click", "tap2click": mode = a
    case "--seconds": if let v = rest.first, let d = Double(v) { seconds = d; rest.removeFirst() }
    case "--log": if let v = rest.first { logPath = v; rest.removeFirst() }
    case "--ask-input-monitoring": askInputMonitoring = true
    default: break
    }
}

// ---- log (stdout and file; called from another thread, hence the lock) -----------
final class Log {
    private let lock = NSLock()
    private var handle: FileHandle?
    private let start = Date()
    init(path: String?) {
        if let path = path {
            FileManager.default.createFile(atPath: path, contents: nil)
            handle = FileHandle(forWritingAtPath: path)
        }
    }
    func line(_ s: String) {
        let t = String(format: "%7.3f", Date().timeIntervalSince(start))
        let data = "[\(t)] \(s)\n".data(using: .utf8)!
        lock.lock(); defer { lock.unlock() }
        FileHandle.standardOutput.write(data)
        handle?.write(data)
    }
}
let log = Log(path: logPath)
log.line("TouchProbe mode=\(mode) seconds=\(seconds) pid=\(getpid())")
func inputMonitoringStatus() -> String {
    let a = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue
    if a == kIOHIDAccessTypeGranted.rawValue { return "granted" }
    if a == kIOHIDAccessTypeDenied.rawValue { return "denied" }
    return "not asked yet"
}
log.line("bundle=\(Bundle.main.bundleIdentifier ?? "none") accessibilityTrusted=\(AXIsProcessTrusted()) inputMonitoring=\(inputMonitoringStatus())")
if askInputMonitoring && IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue != kIOHIDAccessTypeGranted.rawValue {
    let ok = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    log.line("asked for input monitoring: granted=\(ok)")
}

// ---- synthesized right click ------------------------------------------------------
func postRightClick() {
    guard let loc = CGEvent(source: nil)?.location else { log.line("cursor location unavailable"); return }
    let src = CGEventSource(stateID: .hidSystemState)
    guard let down = CGEvent(mouseEventSource: src, mouseType: .rightMouseDown, mouseCursorPosition: loc, mouseButton: .right),
          let up   = CGEvent(mouseEventSource: src, mouseType: .rightMouseUp,   mouseCursorPosition: loc, mouseButton: .right)
    else { log.line("could not create mouse events"); return }
    down.setIntegerValueField(.mouseEventClickState, value: 1)
    up.setIntegerValueField(.mouseEventClickState, value: 1)
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    log.line("posted right click at (\(Int(loc.x)), \(Int(loc.y)))")
}

// ---- tap detection ----------------------------------------------------------------
// When every finger has lifted: short, barely moved, and fingers down at once == fingers seen → a tap.
final class TapDetector {
    struct Contact { var startX: Float; var startY: Float; var maxMove: Float }
    private var contacts: [Int32: Contact] = [:]
    private var touchStart: Double? = nil
    private var maxSimultaneous = 0
    var onTap: ((Int) -> Void)?
    let maxDuration = 0.30
    let maxMove: Float = 0.03

    func frame(_ touches: UnsafeBufferPointer<MTTouch>, timestamp: Double) -> (touching: Int, inRange: Int) {
        var touching = 0
        for t in touches where t.state == 3 || t.state == 4 {
            touching += 1
            let p = t.normalized.position
            if var c = contacts[t.identifier] {
                let d = hypotf(p.x - c.startX, p.y - c.startY)
                if d > c.maxMove { c.maxMove = d; contacts[t.identifier] = c }
            } else {
                contacts[t.identifier] = Contact(startX: p.x, startY: p.y, maxMove: 0)
            }
        }
        if touching > 0 {
            if touchStart == nil { touchStart = timestamp; maxSimultaneous = 0 }
            maxSimultaneous = max(maxSimultaneous, touching)
        } else if let start = touchStart {
            let duration = timestamp - start
            let moved = contacts.values.map { $0.maxMove }.max() ?? 0
            let fingers = contacts.count
            let isTap = duration <= maxDuration && moved <= maxMove && fingers == maxSimultaneous
            log.line(String(format: "lift: fingers=%d simultaneous=%d duration=%.3fs moved=%.3f %@",
                            fingers, maxSimultaneous, duration, moved, isTap ? "=> TAP\(fingers)" : ""))
            if isTap { onTap?(fingers) }
            touchStart = nil; contacts.removeAll(); maxSimultaneous = 0
        }
        return (touching, touches.count)
    }
}
let detector = TapDetector()
var lastTouching = -1
var frameCount = 0

// Passed as a C function pointer, so it captures nothing and uses globals only.
let callback: MTContactCallback = { _, touches, count, timestamp, _ in
    guard let touches = touches else { return 0 }
    frameCount += 1
    if frameCount == 1 { log.line("first frame received") }
    let buf = UnsafeBufferPointer(start: touches, count: Int(count))
    let r = detector.frame(buf, timestamp: timestamp)
    if r.touching != lastTouching {
        lastTouching = r.touching
        let desc = buf.filter { $0.state == 3 || $0.state == 4 }
            .map { String(format: "#%d(%.2f,%.2f)", $0.identifier, $0.normalized.position.x, $0.normalized.position.y) }
            .joined(separator: " ")
        log.line("touching=\(r.touching) inRange=\(r.inRange) \(desc)")
    }
    return 0
}

// ---- main -------------------------------------------------------------------------
if mode == "click" || mode == "tap2click" {
    if !AXIsProcessTrusted() {
        log.line("accessibility NOT trusted: asking the system to show the permission dialog")
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}

if mode == "click" {
    log.line("posting a right click in 3 seconds; keep the cursor where you want it")
    RunLoop.main.run(until: Date().addingTimeInterval(3))
    postRightClick()
    exit(0)
}

var err = [CChar](repeating: 0, count: 256)
if mt_load(&err, 256) != 0 {
    log.line("MultitouchSupport load failed: \(String(cString: err))")
    exit(1)
}
let list = mt_device_list()
let n = CFArrayGetCount(list)
log.line("multitouch devices: \(n)")
var devices: [MTDeviceRef] = []
for i in 0..<n {
    guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
    let dev = UnsafeMutableRawPointer(mutating: raw)
    log.line("device \(i): builtin=\(mt_is_builtin(dev))")
    mt_register(dev, callback)
    mt_start(dev)
    devices.append(dev)
}
if mode == "tap2click" {
    detector.onTap = { fingers in if fingers == 2 { postRightClick() } }
    log.line("two-finger tap => right click, for \(Int(seconds)) seconds")
} else {
    log.line("listening for \(Int(seconds)) seconds; touch the trackpad now")
}
RunLoop.main.run(until: Date().addingTimeInterval(seconds))
for d in devices { mt_stop(d); mt_unregister(d, callback) }
log.line("done: frames received=\(frameCount)")
