import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let store = ConfigStore()
    private lazy var document = ConfigDocument(store: store)
    private let settings = SettingsWindowController()
    private var config = Config()
    private var configErrors: [String] = []

    private let multitouch = MultitouchEngine.shared
    private let recognizer = GestureRecognizer()
    private let corners = HotCornerWatcher()
    private let keyTap = KeyBindingTap()
    private var mouseMonitor: Any?
    private var trustTimer: Timer?
    private var trusted = false
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--print-config") {
            // Debugging aid: show how the settings window would write the current file, then quit.
            print(document.jsonText())
            exit(0)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        store.ensureExists()
        reload(interactive: false)
        trusted = AXIsProcessTrusted()
        if !trusted { requestAccessibility() }
        wire()
        applyConfig()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.pollTrust() }
        // Without this, App Nap may slow the timers of a background app that shows no window.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Listening to the trackpad")
        observeWake()
        logger.notice("started; accessibility trusted=\(self.trusted)")
        if CommandLine.arguments.contains("--open-settings") { openSettings() }
    }

    /// The multitouch callbacks can stop silently after sleep; start them again once the Mac is awake.
    private func observeWake() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                logger.notice("\(note.name.rawValue, privacy: .public): restarting the trackpad listener")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.multitouch.restart() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        multitouch.stop()
        corners.stop()
        keyTap.stop()
    }

    // MARK: Wiring

    private func wire() {
        multitouch.onFrame = { [weak self] points, timestamp in self?.recognizer.frame(points, timestamp: timestamp) }
        recognizer.onGesture = { [weak self] gesture in self?.handle(gesture) }
        corners.onTrigger = { [weak self] _, action in self?.perform(action) }
        keyTap.onAction = { [weak self] action in self?.perform(action) }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            if let cgEvent = event.cgEvent, Synth.isOurs(cgEvent) { return }
            self?.recognizer.physicalClick()
        }
        document.onSaved = { [weak self] in
            guard let self else { return }
            self.reload(interactive: false)
            self.applyConfig()
        }
        settings.onVisibilityChange = { [weak self] _ in self?.applyConfig() }
    }

    /// An edge swipe without its own binding counts as the plain swipe in that direction.
    private func handle(_ gesture: TrackpadGesture) {
        var action = config.gestures[gesture]
        if action == nil, case .edgeSwipe(let fingers, let edge) = gesture {
            action = config.gestures[.swipe(fingers: fingers, direction: edge.swipeDirection)]
        }
        guard let action else { return }
        logger.notice("gesture \(gesture.name, privacy: .public) -> \(action.label, privacy: .public)")
        perform(action)
    }

    private func perform(_ action: Action) {
        if case .openApp = action {
            Synth.perform(action)
            return
        }
        guard trusted else {
            logger.error("accessibility not granted; dropping \(action.label, privacy: .public)")
            return
        }
        Synth.perform(action)
    }

    private func applyConfig() {
        recognizer.tapMaxDuration = config.tuning.tapMaxDuration
        recognizer.tapMaxMove = config.tuning.tapMaxMove
        recognizer.swipeMinDistance = config.tuning.swipeMinDistance
        recognizer.swipeMaxDuration = config.tuning.swipeMaxDuration
        recognizer.edgeBand = config.tuning.edgeBand
        if config.gestures.isEmpty { multitouch.stop() } else { _ = multitouch.start() }

        corners.bindings = config.corners
        corners.defaultDwell = config.tuning.cornerDwell
        corners.tolerance = config.tuning.cornerTolerance
        if config.corners.isEmpty { corners.stop() } else { corners.start() }

        keyTap.bindings = config.keys
        // Paused while the settings window is open, so a combination can be recorded or typed.
        if config.keys.isEmpty || settings.isVisible {
            keyTap.stop()
        } else if trusted {
            _ = keyTap.start()
        }
        rebuildMenu()
    }

    private func reload(interactive: Bool) {
        let (loaded, errors) = store.load()
        config = loaded
        configErrors = errors
        for error in errors { logger.error("config: \(error, privacy: .public)") }
        if interactive && !errors.isEmpty { showErrors() }
    }

    private func pollTrust() {
        let now = AXIsProcessTrusted()
        guard now != trusted else { return }
        trusted = now
        logger.notice("accessibility trusted changed: \(now)")
        applyConfig()
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: Menu

    private func rebuildMenu() {
        let symbol = trusted ? "hand.tap" : "exclamationmark.triangle"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Switchboard Tool")
        image?.isTemplate = true
        statusItem.button?.image = image

        let menu = NSMenu()
        menu.autoenablesItems = false
        addInfo(menu, "Switchboard Tool")
        if trusted {
            addInfo(menu, "Accessibility: granted")
        } else {
            add(menu, "Grant Accessibility Permission…", #selector(openAccessibilitySettings))
        }
        addInfo(menu, summaryLine())
        menu.addItem(.separator())
        add(menu, "Settings…", #selector(openSettings))
        add(menu, "Open Config File", #selector(openConfig))
        add(menu, "Reload Config", #selector(reloadConfig))
        if !configErrors.isEmpty {
            add(menu, "Config Errors: \(configErrors.count)…", #selector(showErrors))
        }
        add(menu, "Show Config in Finder", #selector(revealConfig))
        menu.addItem(.separator())
        let login = add(menu, "Launch at Login", #selector(toggleLoginItem))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        add(menu, "Quit", #selector(quit))
        statusItem.menu = menu
    }

    private func summaryLine() -> String {
        "gestures: \(config.gestures.count) / corners: \(config.corners.count) / keys: \(config.keys.count)"
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private func addInfo(_ menu: NSMenu, _ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    @objc private func openSettings() {
        document.reload()   // pick up edits made by hand since the last save
        settings.show(document: document)
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(store.url)
    }

    @objc private func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([store.url])
    }

    @objc private func reloadConfig() {
        reload(interactive: true)
        applyConfig()
    }

    @objc private func showErrors() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Some parts of the config file could not be read"
        alert.informativeText = configErrors.joined(separator: "\n") + "\n\nRunning with the parts that could be read."
        alert.runModal()
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            logger.error("login item: \(error.localizedDescription, privacy: .public)")
        }
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
