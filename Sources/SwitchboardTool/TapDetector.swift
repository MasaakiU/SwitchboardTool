import Foundation

struct TouchPoint {
    let id: Int32
    let x: Float
    let y: Float
}

/// When every finger has lifted: short, barely moved, and fingers down at once == fingers seen → a tap.
/// A physical click during the touch cancels it (so the system's own secondary click is not doubled). Main thread only.
final class TapDetector {
    var maxDuration: Double = 0.20
    var maxMove: Float = 0.03
    var onTap: ((Int) -> Void)?

    private struct Contact { var startX: Float; var startY: Float; var maxMove: Float }
    private var contacts: [Int32: Contact] = [:]
    private var touchStart: Double?
    private var maxSimultaneous = 0
    private var cancelled = false
    private var silenceTimer: DispatchWorkItem?

    func physicalClick() {
        if touchStart != nil { cancelled = true }
    }

    func frame(_ touching: [TouchPoint], timestamp: Double) {
        silenceTimer?.cancel()
        for touch in touching {
            if var contact = contacts[touch.id] {
                let distance = hypotf(touch.x - contact.startX, touch.y - contact.startY)
                if distance > contact.maxMove { contact.maxMove = distance; contacts[touch.id] = contact }
            } else {
                contacts[touch.id] = Contact(startX: touch.x, startY: touch.y, maxMove: 0)
            }
        }
        if !touching.isEmpty {
            if touchStart == nil { touchStart = timestamp; maxSimultaneous = 0; cancelled = false }
            maxSimultaneous = max(maxSimultaneous, touching.count)
            // If frames stop (all fingers left the sensing range), treat that as the lift
            let item = DispatchWorkItem { [weak self] in self?.finish(at: timestamp + 0.15) }
            silenceTimer = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
        } else if touchStart != nil {
            finish(at: timestamp)
        }
    }

    private func finish(at timestamp: Double) {
        guard let start = touchStart else { return }
        let duration = timestamp - start
        let moved = contacts.values.map { $0.maxMove }.max() ?? 0
        let fingers = contacts.count
        let isTap = !cancelled && fingers > 0 && fingers == maxSimultaneous
            && duration <= maxDuration && moved <= maxMove
        logger.debug("lift fingers=\(fingers) simultaneous=\(self.maxSimultaneous) duration=\(duration) moved=\(moved) cancelled=\(self.cancelled) tap=\(isTap)")
        touchStart = nil
        contacts.removeAll()
        maxSimultaneous = 0
        cancelled = false
        if isTap { onTap?(fingers) }
    }
}
