import Foundation

struct TouchPoint {
    let id: Int32
    let x: Float   // 0…1, left to right
    let y: Float   // 0…1, bottom (near the user) to top (near the keyboard)
}

/// Turns finger frames into gestures. One "session" runs from the first finger down to the last finger up.
/// - A swipe fires as soon as all fingers have moved far enough in one direction (not at lift, for speed).
///   If every finger started inside the band along the edge the swipe moves away from, it is an edge swipe.
/// - A tap is a session that ended quickly, barely moved, had no swipe and no physical click.
/// Main thread only.
final class GestureRecognizer {
    var tapMaxDuration: Double = 0.20
    var tapMaxMove: Float = 0.03
    var swipeMinDistance: Float = 0.20
    var swipeMaxDuration: Double = 0.6
    var edgeBand: Float = 0.08
    var onGesture: ((TrackpadGesture) -> Void)?

    private struct Contact { var startX: Float; var startY: Float; var maxMove: Float }
    private var contacts: [Int32: Contact] = [:]
    private var sessionStart: Double?
    private var maxSimultaneous = 0
    private var cancelled = false
    private var swipeFired = false
    private var silenceTimer: DispatchWorkItem?

    func physicalClick() {
        if sessionStart != nil { cancelled = true }
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
            if sessionStart == nil { sessionStart = timestamp; maxSimultaneous = 0; cancelled = false; swipeFired = false }
            maxSimultaneous = max(maxSimultaneous, touching.count)
            if !swipeFired, !cancelled, let gesture = detectSwipe(touching, timestamp: timestamp) {
                swipeFired = true
                logger.info("swipe \(gesture.name, privacy: .public)")
                onGesture?(gesture)
            }
            // If frames stop (all fingers left the sensing range), treat that as the lift
            let item = DispatchWorkItem { [weak self] in self?.finish(at: timestamp + 0.15) }
            silenceTimer = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
        } else if sessionStart != nil {
            finish(at: timestamp)
        }
    }

    private func detectSwipe(_ touching: [TouchPoint], timestamp: Double) -> TrackpadGesture? {
        guard let start = sessionStart, timestamp - start <= swipeMaxDuration else { return nil }
        let count = touching.count
        // every finger that has touched in this session must still be down
        guard count >= 2, count == maxSimultaneous, count == contacts.count else { return nil }
        var dxs: [Float] = [], dys: [Float] = []
        for touch in touching {
            guard let contact = contacts[touch.id] else { return nil }
            dxs.append(touch.x - contact.startX)
            dys.append(touch.y - contact.startY)
        }
        let dx = dxs.reduce(0, +) / Float(count)
        let dy = dys.reduce(0, +) / Float(count)
        guard hypotf(dx, dy) >= swipeMinDistance else { return nil }
        // all fingers move the same way, each by at least half the distance
        for index in 0..<count {
            guard dxs[index] * dx + dys[index] * dy > 0, hypotf(dxs[index], dys[index]) >= swipeMinDistance * 0.5 else { return nil }
        }
        // one axis has to dominate clearly
        let horizontal = abs(dx) > abs(dy)
        guard (horizontal ? abs(dy) / abs(dx) : abs(dx) / abs(dy)) < 0.6 else { return nil }
        let direction: SwipeDirection = horizontal ? (dx > 0 ? .right : .left) : (dy > 0 ? .up : .down)

        let edge: TrackpadEdge
        switch direction {
        case .down: edge = .top
        case .up: edge = .bottom
        case .right: edge = .left
        case .left: edge = .right
        }
        let startedAtEdge = contacts.values.allSatisfy { contact in
            switch edge {
            case .top: return contact.startY >= 1 - edgeBand
            case .bottom: return contact.startY <= edgeBand
            case .left: return contact.startX <= edgeBand
            case .right: return contact.startX >= 1 - edgeBand
            }
        }
        return startedAtEdge ? .edgeSwipe(fingers: count, edge: edge) : .swipe(fingers: count, direction: direction)
    }

    private func finish(at timestamp: Double) {
        guard let start = sessionStart else { return }
        let duration = timestamp - start
        let moved = contacts.values.map { $0.maxMove }.max() ?? 0
        let fingers = contacts.count
        let isTap = !cancelled && !swipeFired && fingers >= 2 && fingers == maxSimultaneous
            && duration <= tapMaxDuration && moved <= tapMaxMove
        logger.debug("lift fingers=\(fingers) simultaneous=\(self.maxSimultaneous) duration=\(duration) moved=\(moved) cancelled=\(self.cancelled) swipe=\(self.swipeFired) tap=\(isTap)")
        sessionStart = nil
        contacts.removeAll()
        maxSimultaneous = 0
        cancelled = false
        swipeFired = false
        if isTap { onGesture?(.tap(fingers: fingers)) }
    }
}
