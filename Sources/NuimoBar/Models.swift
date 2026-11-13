import AppKit
import Foundation

enum Gesture: String, Codable, CaseIterable, Identifiable {
    case press, longPress
    case swipeLeft, swipeRight, swipeUp, swipeDown
    case touchLeft, touchRight, touchTop, touchBottom
    case longTouchLeft, longTouchRight, longTouchTop, longTouchBottom
    case flyLeft, flyRight, wave

    var id: String { rawValue }

    var label: String {
        switch self {
        case .press: return "Press"
        case .longPress: return "Long press"
        case .swipeLeft: return "Swipe left"
        case .swipeRight: return "Swipe right"
        case .swipeUp: return "Swipe up"
        case .swipeDown: return "Swipe down"
        case .touchLeft: return "Tap left edge"
        case .touchRight: return "Tap right edge"
        case .touchTop: return "Tap top edge"
        case .touchBottom: return "Tap bottom edge"
        case .longTouchLeft: return "Hold left edge"
        case .longTouchRight: return "Hold right edge"
        case .longTouchTop: return "Hold top edge"
        case .longTouchBottom: return "Hold bottom edge"
        case .flyLeft: return "Wave left (above)"
        case .flyRight: return "Wave right (above)"
        case .wave: return "Quick wave over the top"
        }
    }
}

struct KeyCombo: Codable, Hashable {
    var keyCode: UInt16
    /// Raw `NSEvent.ModifierFlags`, limited to ⌃⌥⇧⌘.
    var modifiers: UInt
    var display: String

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], key: String) {
        self.keyCode = keyCode
        let m = modifiers.intersection([.control, .option, .shift, .command])
        self.modifiers = m.rawValue
        var s = ""
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        self.display = s + key
    }

    init(event: NSEvent) {
        self.init(keyCode: event.keyCode, modifiers: event.modifierFlags,
                  key: Self.name(for: event))
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    private static let special: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static func name(for e: NSEvent) -> String {
        if let s = special[e.keyCode] { return s }
        return (e.charactersIgnoringModifiers ?? "?").uppercased()
    }
}

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case inherit, none, playPause, nextTrack, previousTrack, muteToggle
    case missionControl, appWindows, showDesktop, spaceLeft, spaceRight
    case keystroke, shell, shortcut, showEmoji

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inherit: return "Same as Default"
        case .none: return "Nothing"
        case .playPause: return "Play / Pause"
        case .nextTrack: return "Next track"
        case .previousTrack: return "Previous track"
        case .muteToggle: return "Mute / Unmute"
        case .missionControl: return "Mission Control"
        case .appWindows: return "App Windows (Exposé)"
        case .showDesktop: return "Show Desktop"
        case .spaceLeft: return "Space to the left"
        case .spaceRight: return "Space to the right"
        case .keystroke: return "Keystroke"
        case .shell: return "Shell command"
        case .shortcut: return "Run Shortcut"
        case .showEmoji: return "Show emoji on Nuimo"
        }
    }
}

struct Action: Codable, Hashable {
    var kind: ActionKind = .none
    var key: KeyCombo?
    /// Shell command or Shortcut name.
    var text: String = ""
}

enum DialKind: String, Codable, CaseIterable, Identifiable {
    case inherit, none, volume, scrollVertical, scrollHorizontal, keys

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inherit: return "Same as Default"
        case .none: return "Nothing"
        case .volume: return "System volume"
        case .scrollVertical: return "Scroll up / down"
        case .scrollHorizontal: return "Scroll left / right"
        case .keys: return "Keystrokes"
        }
    }
}

struct DialAction: Codable, Hashable {
    var kind: DialKind = .none
    var clockwise: KeyCombo?
    var counterClockwise: KeyCombo?
    /// Keystrokes sent per full turn when `kind == .keys`.
    var stepsPerTurn: Int = 24
    /// Multiplier on how far a given movement goes; 1 is the standard feel.
    var sensitivity: Double = 1.0

    init(kind: DialKind = .none, clockwise: KeyCombo? = nil, counterClockwise: KeyCombo? = nil,
         stepsPerTurn: Int = 24, sensitivity: Double = 1.0) {
        self.kind = kind
        self.clockwise = clockwise
        self.counterClockwise = counterClockwise
        self.stepsPerTurn = stepsPerTurn
        self.sensitivity = sensitivity
    }

    /// Tolerates configs saved before a field existed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(DialKind.self, forKey: .kind) ?? .none
        clockwise = try c.decodeIfPresent(KeyCombo.self, forKey: .clockwise)
        counterClockwise = try c.decodeIfPresent(KeyCombo.self, forKey: .counterClockwise)
        stepsPerTurn = try c.decodeIfPresent(Int.self, forKey: .stepsPerTurn) ?? 24
        sensitivity = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 1.0
    }
}

struct Profile: Codable, Identifiable, Hashable {
    static let defaultID = "default"

    /// `"default"` or an app's bundle identifier.
    var id: String
    var name: String
    var dial = DialAction()
    /// What raising and lowering a hand above the Nuimo does.
    var hover = DialAction()
    var gestures: [String: Action] = [:]

    var isDefault: Bool { id == Self.defaultID }

    init(id: String, name: String, dial: DialAction = DialAction(),
         hover: DialAction? = nil, gestures: [String: Action] = [:]) {
        self.id = id
        self.name = name
        self.dial = dial
        self.hover = hover ?? DialAction(kind: id == Self.defaultID ? .none : .inherit)
        self.gestures = gestures
    }

    /// Tolerates configs saved before a field existed, so upgrades keep the user's mappings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        dial = try c.decodeIfPresent(DialAction.self, forKey: .dial) ?? DialAction()
        hover = try c.decodeIfPresent(DialAction.self, forKey: .hover)
            ?? DialAction(kind: id == Self.defaultID ? .none : .inherit)
        gestures = try c.decodeIfPresent([String: Action].self, forKey: .gestures) ?? [:]
    }

    func action(for g: Gesture) -> Action {
        gestures[g.rawValue] ?? Action(kind: isDefault ? .none : .inherit)
    }
}

/// Shows an emoji on the Nuimo when a matching notification banner appears.
struct NotificationRule: Codable, Identifiable, Hashable {
    var id = UUID()
    /// App name as shown on the banner; empty matches any app.
    var app = ""
    /// Optional text the title or body must contain.
    var contains = ""
    var emoji = "🔔"
    var seconds: Double = 5

    func matches(app bannerApp: String, text: String) -> Bool {
        if !app.isEmpty, bannerApp.caseInsensitiveCompare(app) != .orderedSame { return false }
        return contains.isEmpty || text.localizedCaseInsensitiveContains(contains)
    }
}

struct Config: Codable {
    var profiles: [Profile]
    var ledFeedback = true
    var notificationRules: [NotificationRule] = []

    init(profiles: [Profile], ledFeedback: Bool = true, notificationRules: [NotificationRule] = []) {
        self.profiles = profiles
        self.ledFeedback = ledFeedback
        self.notificationRules = notificationRules
    }

    /// Tolerates configs saved before a field existed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try c.decode([Profile].self, forKey: .profiles)
        ledFeedback = try c.decodeIfPresent(Bool.self, forKey: .ledFeedback) ?? true
        notificationRules = try c.decodeIfPresent([NotificationRule].self, forKey: .notificationRules) ?? []
    }

    static let starter = Config(profiles: [
        Profile(
            id: Profile.defaultID, name: "Default",
            dial: DialAction(kind: .volume),
            gestures: [
                Gesture.press.rawValue: Action(kind: .playPause),
                Gesture.longPress.rawValue: Action(kind: .muteToggle),
                Gesture.swipeRight.rawValue: Action(kind: .nextTrack),
                Gesture.swipeLeft.rawValue: Action(kind: .previousTrack),
            ]),
        Profile(
            id: "com.adobe.Photoshop", name: "Adobe Photoshop",
            dial: DialAction(
                kind: .keys,
                clockwise: KeyCombo(keyCode: 30, key: "]"),
                counterClockwise: KeyCombo(keyCode: 33, key: "["),
                stepsPerTurn: 24),
            gestures: [
                Gesture.swipeLeft.rawValue: Action(kind: .keystroke, key: KeyCombo(keyCode: 6, modifiers: .command, key: "Z")),
                Gesture.swipeRight.rawValue: Action(kind: .keystroke, key: KeyCombo(keyCode: 6, modifiers: [.command, .shift], key: "Z")),
            ]),
    ])
}

/// Loads and saves the mappings as JSON in Application Support.
final class ConfigStore: ObservableObject {
    @Published var config: Config { didSet { save() } }

    let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NuimoBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(Config.self, from: data),
           loaded.profiles.contains(where: \.isDefault) {
            config = loaded
        } else {
            config = .starter
            save()
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(config) { try? data.write(to: fileURL, options: .atomic) }
    }

    var defaultProfile: Profile { config.profiles.first(where: \.isDefault)! }

    func profile(forBundleID id: String?) -> Profile? {
        guard let id else { return nil }
        return config.profiles.first { $0.id == id }
    }

    /// The action for a gesture given the frontmost app, falling back to Default.
    func action(for g: Gesture, bundleID: String?) -> Action {
        if let a = profile(forBundleID: bundleID)?.action(for: g), a.kind != .inherit { return a }
        return defaultProfile.action(for: g)
    }

    func dial(bundleID: String?) -> DialAction {
        if let d = profile(forBundleID: bundleID)?.dial, d.kind != .inherit { return d }
        return defaultProfile.dial
    }

    func hover(bundleID: String?) -> DialAction {
        if let h = profile(forBundleID: bundleID)?.hover, h.kind != .inherit { return h }
        return defaultProfile.hover
    }

    func addProfile(bundleID: String, name: String) {
        guard !config.profiles.contains(where: { $0.id == bundleID }) else { return }
        config.profiles.append(Profile(id: bundleID, name: name, dial: DialAction(kind: .inherit)))
    }

    func removeProfile(id: String) {
        guard id != Profile.defaultID else { return }
        config.profiles.removeAll { $0.id == id }
    }
}
