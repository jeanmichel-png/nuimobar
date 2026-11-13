import AppKit
import Foundation

/// Glue: takes input from the Nuimo, looks up the mapping for the frontmost
/// app and performs it, with feedback on the LED matrix.
final class Controller: ObservableObject {
    let device = NuimoDevice()
    let store = ConfigStore()

    /// Most recent input first, for the live view in Settings.
    @Published private(set) var events: [String] = []

    private var keyAccumulator = 0.0
    private var scrollAccumulator = 0.0
    private var lastRotation = Date.distantPast

    init() {
        device.onGesture = { [weak self] g in self?.handle(g) }
        device.onRotate = { [weak self] d in self?.handleRotation(d) }
        device.onHover = { [weak self] h in self?.handleHover(h) }
        device.onRaw = { [weak self] name, bytes in self?.logRaw(name, bytes) }
        notifications.onBanner = { [weak self] banner in self?.handle(banner) }
        notifications.start()
        logRaw("accessibility \(SystemActions.canPostEvents ? "granted" : "NOT granted")", [])
        // Lets scripts draw on the display: post a distributed notification named
        // "co.theforge.NuimoBar.led" whose object is "<81 cells>|<seconds>|<brightness>"
        // or "emoji:<character>|<seconds>|<brightness>".
        // Cells run row by row; "#" or "1" is lit. Seconds and brightness are optional.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("co.theforge.NuimoBar.led"), object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let text = note.object as? String else { return }
            let parts = text.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            var matrix = LEDMatrix()
            let pattern = parts.first ?? ""
            if pattern.hasPrefix("emoji:"), let glyph = pattern.dropFirst(6).first {
                matrix = LEDMatrix(glyph: String(glyph))
            } else {
                for (i, ch) in pattern.prefix(81).enumerated() where ch == "#" || ch == "1" {
                    matrix.bits[i] = true
                }
            }
            let seconds = parts.count > 1 ? Double(parts[1]) ?? 1.5 : 1.5
            let brightness = parts.count > 2 ? Double(parts[2]) ?? 1.0 : 1.0
            self.device.show(matrix, brightness: brightness, seconds: seconds)
        }
        device.onConnect = { [weak self] in
            guard let self else { return }
            self.log("Connected")
            if self.store.config.ledFeedback { self.device.show(.hello, seconds: 1.0, fade: true) }
        }
    }

    private var frontBundleID: String? {
        let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return id == Bundle.main.bundleIdentifier ? nil : id
    }

    private func log(_ s: String) {
        events.insert(s, at: 0)
        if events.count > 40 { events.removeLast(events.count - 40) }
    }

    /// Raw sensor bytes go to ~/Library/Logs/NuimoBar/raw.log for diagnosing gestures.
    private lazy var rawLog: FileHandle? = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/NuimoBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("raw.log")
        // Keep history across launches so intermittent problems can be traced, but cap the size.
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        if size == nil || size! > 1_000_000 {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try? FileHandle(forWritingTo: url)
        handle?.seekToEndOfFile()
        return handle
    }()

    private func logRaw(_ name: String, _ bytes: [UInt8]) {
        let hex = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        let line = String(format: "%.2f %@ %@\n", Date().timeIntervalSince1970, name, hex)
        rawLog?.write(Data(line.utf8))
        // Surface the touch and hover sensors in the live view so it is obvious
        // whether the Nuimo is reporting them at all.
        if name == "touch" || name == "fly" {
            log("Sensor \(name == "fly" ? "hover" : "touch"): \(hex)")
        }
    }

    private func show(_ m: LEDMatrix, seconds: Double = 1.0) {
        if store.config.ledFeedback { device.show(m, seconds: seconds) }
    }

    // MARK: Notifications

    private let notifications = NotificationWatcher()

    /// Apps seen notifying since launch, offered when writing a rule.
    @Published private(set) var recentNotificationApps: [String] = []

    private func handle(_ banner: NotificationWatcher.Banner) {
        logRaw("banner app=\(banner.app)", [])
        if !recentNotificationApps.contains(banner.app) {
            recentNotificationApps.insert(banner.app, at: 0)
            if recentNotificationApps.count > 12 { recentNotificationApps.removeLast() }
        }
        let text = banner.title + " " + banner.body
        if let rule = store.config.notificationRules.first(where: { $0.matches(app: banner.app, text: text) }),
           let glyph = rule.emoji.first {
            log("Notification from \(banner.app) → \(rule.emoji)")
            logRaw("banner matched rule \(rule.emoji)", [])
            device.show(LEDMatrix(glyph: String(glyph)), seconds: rule.seconds, fade: true)
        } else {
            log("Notification from \(banner.app) (no rule)")
        }
    }

    // MARK: Gestures

    private func handle(_ g: Gesture) {
        if g == .flyLeft || g == .flyRight {
            // One physical wave often reports both directions a fraction of a
            // second apart; keep the first. The same pass also streams height
            // readings, which must not count as a hover or a quick wave.
            let now = Date()
            guard now.timeIntervalSince(lastDirectionalWave) > 0.6 else { return }
            lastDirectionalWave = now
            hoverSuppressedUntil = now.addingTimeInterval(0.6)
            hoverEndTimer?.invalidate()
            hoverEngaged = false
        }
        let action = store.action(for: g, bundleID: frontBundleID)
        log("\(g.label) → \(describe(action))")
        logRaw("gesture \(g.rawValue) -> \(action.kind.rawValue)", [])
        switch action.kind {
        case .inherit, .none:
            break
        case .playPause:
            SystemActions.press(.play); show(.playPause)
        case .nextTrack:
            SystemActions.press(.next); show(.next)
        case .previousTrack:
            SystemActions.press(.previous); show(.previous)
        case .muteToggle:
            if let muted = SystemActions.toggleMute() {
                show(muted ? .mute : .level(Double(SystemActions.volume ?? 0)))
            }
        case .missionControl:
            SystemActions.dock(.missionControl); show(.dot, seconds: 0.3)
        case .appWindows:
            SystemActions.dock(.appWindows); show(.dot, seconds: 0.3)
        case .showDesktop:
            SystemActions.dock(.showDesktop); show(.dot, seconds: 0.3)
        case .spaceLeft:
            SystemActions.send(KeyCombo(keyCode: 123, modifiers: .control, key: "←")); show(.previous, seconds: 0.4)
        case .spaceRight:
            SystemActions.send(KeyCombo(keyCode: 124, modifiers: .control, key: "→")); show(.next, seconds: 0.4)
        case .keystroke:
            if let k = action.key { SystemActions.send(k); show(.dot, seconds: 0.3) }
        case .shell:
            SystemActions.runShell(action.text); show(.dot, seconds: 0.3)
        case .shortcut:
            SystemActions.runShortcut(action.text); show(.dot, seconds: 0.3)
        case .showEmoji:
            // Deliberate output, so it ignores the feedback toggle.
            if let first = action.text.first { device.show(LEDMatrix(glyph: String(first)), seconds: 3) }
        }
    }

    private func describe(_ a: Action) -> String {
        switch a.kind {
        case .keystroke: return a.key?.display ?? "Keystroke (not set)"
        case .showEmoji: return "Show \(a.text)"
        case .shell: return "Shell: \(a.text)"
        case .shortcut: return "Shortcut: \(a.text)"
        default: return a.kind.label
        }
    }

    // MARK: Dial

    private func handleRotation(_ delta: Int) {
        let now = Date()
        if now.timeIntervalSince(lastRotation) > 0.5 {
            // A fresh turn: drop leftovers and log once rather than per tick.
            keyAccumulator = 0
            scrollAccumulator = 0
            let dial = store.dial(bundleID: frontBundleID)
            log("Dial \(delta > 0 ? "clockwise" : "anticlockwise") → \(dial.kind.label)")
        }
        lastRotation = now

        apply(store.dial(bundleID: frontBundleID), turns: Double(delta) / NuimoDevice.unitsPerTurn)
    }

    // MARK: Hover

    private var hoverStart = Date.distantPast
    private var hoverLast = Date.distantPast
    private var hoverPrevious: Int?
    private var hoverEngaged = false
    private var hoverEndTimer: Timer?
    private var hoverBanked = 0
    private var hoverSuppressedUntil = Date.distantPast
    private var lastDirectionalWave = Date.distantPast

    /// The Nuimo reports hand height about eight times a second while a hand is
    /// in range. A hand that stays is a continuous control (raise = more); one
    /// that passes straight through counts as a quick wave.
    private func handleHover(_ height: Int) {
        let now = Date()
        guard now >= hoverSuppressedUntil else { return }
        if now.timeIntervalSince(hoverLast) > 0.4 {
            hoverStart = now
            hoverPrevious = nil
            hoverEngaged = false
            hoverBanked = 0
            keyAccumulator = 0
            scrollAccumulator = 0
        }
        hoverLast = now
        hoverEndTimer?.invalidate()
        hoverEndTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self else { return }
            // A directional wave reported in the meantime takes precedence.
            if !self.hoverEngaged, Date() >= self.hoverSuppressedUntil,
               self.hoverLast.timeIntervalSince(self.hoverStart) < 0.3 {
                self.handle(.wave)
            }
        }
        defer { hoverPrevious = height }
        guard let previous = hoverPrevious else { return }
        var change = height - previous
        // Big jumps are the hand entering or leaving range, not deliberate movement.
        guard abs(change) <= 80 else { return }
        // Until the hand has stayed long enough to rule out a passing wave, bank
        // the movement instead of dropping it, then apply it in one go. Otherwise
        // a quick deliberate raise or lower is mostly over before it counts.
        guard now.timeIntervalSince(hoverStart) >= 0.35 else {
            hoverBanked += change
            return
        }
        change += hoverBanked
        hoverBanked = 0
        guard change != 0 else { return }
        let hover = store.hover(bundleID: frontBundleID)
        if !hoverEngaged {
            hoverEngaged = true
            log("Hover → \(hover.kind.label)")
        }
        apply(hover, turns: Double(change) / 500.0)
    }

    // MARK: Continuous controls

    /// Applies a dial-style action; one "turn" is a full dial rotation or the full hover range.
    private func apply(_ dial: DialAction, turns rawTurns: Double) {
        let turns = rawTurns * max(0.05, dial.sensitivity)
        switch dial.kind {
        case .inherit, .none:
            break
        case .volume:
            if let v = SystemActions.volume {
                let new = max(0, min(1, v + Float(turns)))
                SystemActions.setVolume(new)
                show(.level(Double(new)))
            } else {
                // No software volume on this output: fall back to the volume keys.
                stepKeys(turns, stepsPerTurn: 16) { SystemActions.press($0 ? .soundUp : .soundDown) }
            }
        case .scrollVertical, .scrollHorizontal:
            scrollAccumulator += turns * 1600
            let px = Int32(scrollAccumulator.rounded(.towardZero))
            guard px != 0 else { break }
            scrollAccumulator -= Double(px)
            if dial.kind == .scrollVertical {
                SystemActions.scroll(vertical: -px)
            } else {
                SystemActions.scroll(horizontal: -px)
            }
        case .keys:
            stepKeys(turns, stepsPerTurn: dial.stepsPerTurn) { clockwise in
                if let k = clockwise ? dial.clockwise : dial.counterClockwise { SystemActions.send(k) }
            }
        }
    }

    /// Turns continuous rotation into discrete steps.
    private func stepKeys(_ turns: Double, stepsPerTurn: Int, _ fire: (Bool) -> Void) {
        keyAccumulator += turns * Double(max(1, stepsPerTurn))
        while keyAccumulator >= 1 { keyAccumulator -= 1; fire(true) }
        while keyAccumulator <= -1 { keyAccumulator += 1; fire(false) }
    }
}
