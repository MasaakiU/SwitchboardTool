import AppKit

enum Corner: String, CaseIterable {
    case topLeft = "top_left"
    case topRight = "top_right"
    case bottomLeft = "bottom_left"
    case bottomRight = "bottom_right"
}

struct CornerBinding {
    var action: Action
    var dwell: Double?
}

/// Polls the cursor every 50 ms; fires when it stays in a screen corner for the dwell time. Re-arms only after the cursor leaves the corner.
final class HotCornerWatcher {
    var bindings: [Corner: CornerBinding] = [:]
    var defaultDwell: Double = 0.20
    var tolerance: CGFloat = 2
    var onTrigger: ((Corner, Action) -> Void)?

    private var timer: Timer?
    private var current: Corner?
    private var enteredAt = Date()
    private var fired = false

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        current = nil
    }

    private func tick() {
        let corner = cornerAt(NSEvent.mouseLocation)
        if corner != current {
            current = corner
            enteredAt = Date()
            fired = false
            return
        }
        guard let corner, let binding = bindings[corner], !fired, NSEvent.pressedMouseButtons == 0 else { return }
        if Date().timeIntervalSince(enteredAt) >= (binding.dwell ?? defaultDwell) {
            fired = true
            logger.info("hot corner \(corner.rawValue, privacy: .public)")
            onTrigger?(corner, binding.action)
        }
    }

    private func cornerAt(_ point: NSPoint) -> Corner? {
        for screen in NSScreen.screens {
            let frame = screen.frame
            guard frame.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { continue }
            let left = point.x <= frame.minX + tolerance
            let right = point.x >= frame.maxX - tolerance
            let bottom = point.y <= frame.minY + tolerance
            let top = point.y >= frame.maxY - tolerance
            if top && left { return .topLeft }
            if top && right { return .topRight }
            if bottom && left { return .bottomLeft }
            if bottom && right { return .bottomRight }
        }
        return nil
    }
}
