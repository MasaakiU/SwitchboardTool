import Foundation
import CMultitouch

/// Receives finger frames from the private MultitouchSupport framework and hands the touching fingers to the main thread.
final class MultitouchEngine {
    static let shared = MultitouchEngine()
    var onFrame: (([TouchPoint], Double) -> Void)?

    private var deviceList: CFArray?        // owns the device objects, so keep it alive
    private var devices: [MTDeviceRef] = []
    var isRunning: Bool { !devices.isEmpty }

    func start() -> Bool {
        if isRunning { return true }
        var error = [CChar](repeating: 0, count: 256)
        guard mt_load(&error, 256) == 0 else {
            logger.error("MultitouchSupport unavailable: \(String(cString: error), privacy: .public)")
            return false
        }
        let list = mt_device_list()
        deviceList = list
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            mt_register(device, multitouchTrampoline)
            mt_start(device)
            devices.append(device)
        }
        logger.info("multitouch devices started: \(self.devices.count)")
        return isRunning
    }

    func stop() {
        for device in devices { mt_stop(device); mt_unregister(device, multitouchTrampoline) }
        devices.removeAll()
        deviceList = nil
    }

    fileprivate func receive(_ touches: UnsafeBufferPointer<MTTouch>, timestamp: Double) {
        var points: [TouchPoint] = []
        for touch in touches where touch.state == 3 || touch.state == 4 {
            points.append(TouchPoint(id: touch.identifier, x: touch.normalized.position.x, y: touch.normalized.position.y))
        }
        DispatchQueue.main.async { [points] in self.onFrame?(points, timestamp) }
    }
}

// Passed as a C function pointer, so it must not capture anything.
private let multitouchTrampoline: MTContactCallback = { _, touches, count, timestamp, _ in
    guard let touches = touches else { return 0 }
    MultitouchEngine.shared.receive(UnsafeBufferPointer(start: touches, count: Int(count)), timestamp: timestamp)
    return 0
}
