import Foundation

enum SwipeDirection: String, CaseIterable {
    case left, right, up, down
}

enum TrackpadEdge: String, CaseIterable {
    case top, bottom, left, right

    /// A swipe that starts at an edge moves away from it.
    var swipeDirection: SwipeDirection {
        switch self {
        case .top: return .down
        case .bottom: return .up
        case .left: return .right
        case .right: return .left
        }
    }
}

/// A trackpad gesture as named in the config, e.g. `two_finger_tap`, `three_finger_swipe_left`,
/// `two_finger_swipe_down_from_top`.
enum TrackpadGesture: Hashable, Identifiable {
    case tap(fingers: Int)
    case swipe(fingers: Int, direction: SwipeDirection)
    case edgeSwipe(fingers: Int, edge: TrackpadEdge)

    private static let words: [Int: String] = [1: "one", 2: "two", 3: "three", 4: "four", 5: "five"]
    private static let numbers: [String: Int] = Dictionary(uniqueKeysWithValues: words.map { ($1, $0) })

    var id: String { name }

    var fingers: Int {
        switch self {
        case .tap(let n), .swipe(let n, _), .edgeSwipe(let n, _): return n
        }
    }

    /// The name used in config.json.
    var name: String {
        let word = Self.words[fingers] ?? "\(fingers)"
        switch self {
        case .tap: return "\(word)_finger_tap"
        case .swipe(_, let direction): return "\(word)_finger_swipe_\(direction.rawValue)"
        case .edgeSwipe(_, let edge): return "\(word)_finger_swipe_\(edge.swipeDirection.rawValue)_from_\(edge.rawValue)"
        }
    }

    /// The label shown in the settings window.
    var label: String {
        switch self {
        case .tap(let n): return "\(n)-finger tap"
        case .swipe(let n, let direction): return "\(n)-finger swipe \(direction.rawValue)"
        case .edgeSwipe(let n, let edge): return "\(n)-finger swipe \(edge.swipeDirection.rawValue) from the \(edge.rawValue) edge"
        }
    }

    init?(name: String) {
        let parts = name.split(separator: "_").map(String.init)
        guard parts.count >= 3, let fingers = Self.numbers[parts[0]], parts[1] == "finger" else { return nil }
        if parts.count == 3, parts[2] == "tap" { self = .tap(fingers: fingers); return }
        guard parts[2] == "swipe", parts.count >= 4, let direction = SwipeDirection(rawValue: parts[3]) else { return nil }
        if parts.count == 4 { self = .swipe(fingers: fingers, direction: direction); return }
        guard parts.count == 6, parts[4] == "from", let edge = TrackpadEdge(rawValue: parts[5]),
              edge.swipeDirection == direction else { return nil }
        self = .edgeSwipe(fingers: fingers, edge: edge)
    }

    /// Everything the settings window offers. Plain two-finger swipes are scrolling, so they are left out;
    /// two-finger swipes that start at an edge are offered (the system itself uses the right edge).
    static let catalog: [TrackpadGesture] = {
        var list: [TrackpadGesture] = []
        for n in 2...5 { list.append(.tap(fingers: n)) }
        for n in 3...5 { for direction in SwipeDirection.allCases { list.append(.swipe(fingers: n, direction: direction)) } }
        for n in 2...3 { for edge in TrackpadEdge.allCases { list.append(.edgeSwipe(fingers: n, edge: edge)) } }
        return list
    }()
}
