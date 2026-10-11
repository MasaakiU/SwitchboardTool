import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Corner {
    var label: String {
        switch self {
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        }
    }
}

/// Owns the settings window. Reports when it is shown or closed so key bindings can pause meanwhile.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    var onVisibilityChange: ((Bool) -> Void)?

    var isVisible: Bool { window?.isVisible ?? false }

    func show(document: ConfigDocument) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(document: document))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Switchboard Tool Settings"
            window.setContentSize(NSSize(width: 760, height: 680))
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        onVisibilityChange?(true)
    }

    func windowWillClose(_ notification: Notification) {
        onVisibilityChange?(false)
    }
}

struct SettingsView: View {
    @ObservedObject var document: ConfigDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                gesturesSection
                cornersSection
                keysSection
                tuningSection
                footer
            }
            .padding(20)
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    // MARK: Gestures

    private var gesturesSection: some View {
        GroupBox("Trackpad gestures") {
            VStack(alignment: .leading, spacing: 8) {
                if document.gestures.isEmpty {
                    Text("No gestures yet.").foregroundStyle(.secondary)
                }
                ForEach($document.gestures) { $row in
                    HStack {
                        Picker("", selection: $row.gesture) {
                            ForEach(gestureOptions(including: row.gesture)) { gesture in
                                Text(gesture.label).tag(gesture)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 270)
                        ActionEditor(action: optional($row.action))
                        Spacer()
                        removeButton { document.gestures.removeAll { $0.id == row.id } }
                    }
                }
                Button("Add Gesture") {
                    document.gestures.append(GestureRow(id: UUID(), gesture: .tap(fingers: 3), action: .named(.middleClick)))
                }
                Text("Swipes with three or more fingers are also seen by macOS. Turn the matching system gesture off in System Settings › Trackpad, or both will fire. Edge swipes start inside the band along that edge.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
        }
    }

    private func gestureOptions(including current: TrackpadGesture) -> [TrackpadGesture] {
        TrackpadGesture.catalog.contains(current) ? TrackpadGesture.catalog : TrackpadGesture.catalog + [current]
    }

    // MARK: Hot corners

    private var cornersSection: some View {
        GroupBox("Hot corners") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Corner.allCases, id: \.self) { corner in
                    HStack {
                        Text(corner.label).frame(width: 110, alignment: .leading)
                        ActionEditor(action: cornerBinding(corner), allowNone: true)
                        Spacer()
                    }
                }
                Text("Set the system's own hot corner for the same corner to “–” in System Settings › Desktop & Dock.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private func cornerBinding(_ corner: Corner) -> Binding<ActionSpec?> {
        Binding(
            get: { document.corners[corner]?.action },
            set: { newValue in
                if let newValue {
                    var row = document.corners[corner] ?? CornerRow(action: nil, dwellMs: nil)
                    row.action = newValue
                    document.corners[corner] = row
                } else {
                    document.corners[corner] = nil
                }
            }
        )
    }

    // MARK: Key bindings

    private var keysSection: some View {
        GroupBox("Key bindings") {
            VStack(alignment: .leading, spacing: 8) {
                if document.keys.isEmpty {
                    Text("No key bindings yet.").foregroundStyle(.secondary)
                }
                ForEach($document.keys) { $row in
                    HStack {
                        KeyComboField(combo: $row.combo)
                        ActionEditor(action: optional($row.action))
                        Spacer()
                        removeButton { document.keys.removeAll { $0.id == row.id } }
                    }
                }
                Button("Add Key Binding") {
                    document.keys.append(KeyRow(id: UUID(), combo: "", action: .named(.leftClick)))
                }
                Text("Type the combination (for example ctrl+alt+right) or click Record and press the keys. Key bindings are paused while this window is open.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
        }
    }

    // MARK: Tuning

    private var tuningSection: some View {
        GroupBox("Tuning") {
            VStack(alignment: .leading, spacing: 10) {
                tuningRow("Tap: longest duration", $document.tuning.tapMaxMs, 50...400, 10, "%.0f ms")
                tuningRow("Tap: largest movement", $document.tuning.tapMaxMove, 0.01...0.10, 0.005, "%.3f")
                tuningRow("Swipe: distance", $document.tuning.swipeMinDistance, 0.10...0.50, 0.01, "%.2f")
                tuningRow("Swipe: longest duration", $document.tuning.swipeMaxMs, 200...1200, 50, "%.0f ms")
                tuningRow("Edge swipe: edge band", $document.tuning.edgeBand, 0.03...0.20, 0.01, "%.2f")
                tuningRow("Hot corner: dwell", $document.tuning.cornerDwellMs, 0...1000, 50, "%.0f ms")
                tuningRow("Hot corner: tolerance", $document.tuning.cornerTolerancePx, 1...10, 1, "%.0f px")
                Text("Distances are fractions of the trackpad width (0.03 is about 3 mm).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private func tuningRow(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ step: Double, _ format: String) -> some View {
        HStack {
            Text(title).frame(width: 200, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(String(format: format, value.wrappedValue)).monospacedDigit().frame(width: 70, alignment: .trailing)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Changes are saved to config.json and applied right away.").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button("Open config.json") { NSWorkspace.shared.open(document.fileURL) }
            }
            if !document.skipped.isEmpty {
                Text("Not shown here and dropped on the next save: " + document.skipped.joined(separator: ", "))
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    private func optional(_ binding: Binding<ActionSpec>) -> Binding<ActionSpec?> {
        Binding(get: { binding.wrappedValue }, set: { if let value = $0 { binding.wrappedValue = value } })
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "minus.circle") }
            .buttonStyle(.borderless)
            .help("Remove")
    }
}

/// Picks what a trigger does: a named action, a key combination or an app to open.
struct ActionEditor: View {
    @Binding var action: ActionSpec?
    var allowNone = false

    private enum Kind: Hashable {
        case none, key, openApp, named(NamedAction)
    }

    private var kind: Binding<Kind> {
        Binding(
            get: {
                switch action {
                case nil: return .none
                case .key: return .key
                case .openApp: return .openApp
                case .named(let named): return .named(named)
                }
            },
            set: { newKind in
                switch newKind {
                case .none: action = nil
                case .key: if case .key = action {} else { action = .key("") }
                case .openApp: if case .openApp = action {} else { action = .openApp("") }
                case .named(let named): action = .named(named)
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: kind) {
                if allowNone { Text("None").tag(Kind.none) }
                Text("Key combination…").tag(Kind.key)
                Text("Open app…").tag(Kind.openApp)
                Divider()
                ForEach(NamedAction.allCases) { named in
                    Text(named.label).tag(Kind.named(named))
                }
            }
            .labelsHidden()
            .frame(width: 210)
            switch action {
            case .key(let combo):
                KeyComboField(combo: Binding(get: { combo }, set: { action = .key($0) }))
            case .openApp(let app):
                AppField(app: Binding(get: { app }, set: { action = .openApp($0) }))
            default:
                EmptyView()
            }
        }
    }
}

/// A key combination: typed as text, or recorded by pressing the keys.
struct KeyComboField: View {
    @Binding var combo: String

    var body: some View {
        HStack(spacing: 6) {
            TextField("ctrl+alt+right", text: $combo)
                .textFieldStyle(.roundedBorder)
                .frame(width: 170)
            KeyRecorderButton { combo = $0 }
            if !combo.isEmpty, KeyCodes.parseCombo(combo) == nil {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help("Unknown key name. See KeyCodes.swift for the names.")
            }
        }
    }
}

struct AppField: View {
    @Binding var app: String

    var body: some View {
        HStack(spacing: 6) {
            TextField("Name, bundle id or path", text: $app)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.applicationBundle]
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                panel.directoryURL = URL(fileURLWithPath: "/Applications")
                if panel.runModal() == .OK, let url = panel.url { app = url.path }
            }
        }
    }
}

/// A button that records the next key press as a combination such as "ctrl+alt+right".
struct KeyRecorderButton: NSViewRepresentable {
    var onRecorded: (String) -> Void

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.onRecorded = onRecorded
        return view
    }

    func updateNSView(_ view: KeyRecorderNSView, context: Context) {
        view.onRecorded = onRecorded
    }
}

final class KeyRecorderNSView: NSView {
    var onRecorded: ((String) -> Void)?
    private var recording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 96, height: 24) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        recording = true
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        defer {
            recording = false
            window?.makeFirstResponder(nil)
        }
        if event.keyCode == 53 { return }   // Escape cancels
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)).intersection(KeyCodes.relevantModifiers)
        if let text = KeyCodes.comboText(keyCode: CGKeyCode(event.keyCode), flags: flags) {
            onRecorded?(text)
        } else {
            NSSound.beep()
        }
    }

    override func flagsChanged(with event: NSEvent) {
        // modifier keys alone never finish a recording
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.2) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()
        let text = recording ? "Press keys…" : "Record"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}
