import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: Controller
    @ObservedObject var store: ConfigStore
    @ObservedObject var device: NuimoDevice
    @State private var selection: String? = Profile.defaultID

    static let notificationsID = "__notifications"

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 210)
            Divider()
            VStack(spacing: 0) {
                if selection == Self.notificationsID {
                    NotificationRulesEditor(store: store, controller: controller)
                } else if let profile = selectedProfile {
                    ProfileEditor(profile: profile)
                } else {
                    Spacer()
                    Text("Select a profile").foregroundStyle(.secondary)
                    Spacer()
                }
                Divider()
                LivePanel(controller: controller, store: store, device: device)
            }
        }
        .frame(minWidth: 760, minHeight: 620)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Controls") {
                    ForEach(store.config.profiles) { p in
                        Label(p.name, systemImage: p.isDefault ? "dial.medium" : "app")
                            .tag(Optional(p.id))
                    }
                }
                Section("Display") {
                    Label("Notifications", systemImage: "bell")
                        .tag(Optional(Self.notificationsID))
                }
            }
            Divider()
            HStack {
                Menu {
                    ForEach(addableApps, id: \.id) { app in
                        Button(app.name) {
                            store.addProfile(bundleID: app.id, name: app.name)
                            selection = app.id
                        }
                    }
                    if addableApps.isEmpty { Text("Open the app you want to add first") }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Add a profile for a running app")

                Button {
                    if let id = selection { store.removeProfile(id: id); selection = Profile.defaultID }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selection == nil || selection == Profile.defaultID || selection == Self.notificationsID)
                Spacer()
            }
            .padding(8)
        }
    }

    private var addableApps: [(id: String, name: String)] {
        let existing = Set(store.config.profiles.map(\.id))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, !existing.contains(id) else { return nil }
                return (id, app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedProfile: Binding<Profile>? {
        guard let id = selection, store.config.profiles.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { store.config.profiles.first { $0.id == id } ?? store.defaultProfile },
            set: { new in
                if let i = store.config.profiles.firstIndex(where: { $0.id == id }) {
                    store.config.profiles[i] = new
                }
            })
    }
}

private struct NotificationRulesEditor: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var controller: Controller

    var body: some View {
        Form {
            Section {
                if store.config.notificationRules.isEmpty {
                    Text("No rules yet. Add one to show an emoji when an app notifies you.")
                        .foregroundStyle(.secondary)
                }
                ForEach($store.config.notificationRules) { $rule in
                    HStack {
                        TextField("", text: $rule.emoji, prompt: Text("🔔"))
                            .textFieldStyle(.roundedBorder).frame(width: 44)
                        TextField("", text: $rule.app, prompt: Text("Any app"))
                            .textFieldStyle(.roundedBorder).frame(minWidth: 110)
                        Menu {
                            Button("Any app") { rule.app = "" }
                            Divider()
                            ForEach(appNames, id: \.self) { name in Button(name) { rule.app = name } }
                        } label: { Image(systemName: "chevron.down") }
                            .menuStyle(.borderlessButton).fixedSize()
                        TextField("", text: $rule.contains, prompt: Text("containing… (optional)"))
                            .textFieldStyle(.roundedBorder).frame(minWidth: 120)
                        Stepper("\(Int(rule.seconds)) s", value: $rule.seconds, in: 1...25).fixedSize()
                        Button {
                            store.config.notificationRules.removeAll { $0.id == rule.id }
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add Rule") { store.config.notificationRules.append(NotificationRule()) }
            } header: {
                Text("When a notification arrives, show an emoji")
            } footer: {
                Text("The first matching rule wins, so put specific rules above an “Any app” one. Only banners that actually appear on screen are seen, so notifications hidden by a Focus mode are not shown on the Nuimo.")
            }
        }
        .formStyle(.grouped)
    }

    /// Apps that have notified since launch first, then running apps.
    private var appNames: [String] {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.localizedName)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        var seen = Set<String>()
        return (controller.recentNotificationApps + running).filter { seen.insert($0).inserted }
    }
}

private struct ProfileEditor: View {
    @Binding var profile: Profile

    var body: some View {
        Form {
            Section {
                ContinuousEditor(action: $profile.dial, allowInherit: !profile.isDefault,
                                 title: "Turn", more: "Clockwise", less: "Anticlockwise",
                                 steps: "Steps per full turn")
            } header: {
                Text(profile.isDefault ? "Dial" : "Dial in \(profile.name)")
            }

            Section {
                ContinuousEditor(action: $profile.hover, allowInherit: !profile.isDefault,
                                 title: "Raise / lower hand", more: "Raise", less: "Lower",
                                 steps: "Steps over full height")
            } header: {
                Text("Hover")
            } footer: {
                Text("Hold a hand a few centimetres above the Nuimo, then raise or lower it.")
            }

            Section("Gestures") {
                ForEach(Gesture.allCases) { g in
                    ActionRow(title: g.label, action: binding(for: g), allowInherit: !profile.isDefault)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for g: Gesture) -> Binding<Action> {
        Binding(get: { profile.action(for: g) },
                set: { profile.gestures[g.rawValue] = $0 })
    }
}

private struct ContinuousEditor: View {
    @Binding var action: DialAction
    let allowInherit: Bool
    let title: String
    let more: String
    let less: String
    let steps: String

    var body: some View {
        Picker(title, selection: $action.kind) {
            ForEach(DialKind.allCases.filter { $0 != .inherit || allowInherit }) {
                Text($0.label).tag($0)
            }
        }
        if action.kind != .none && action.kind != .inherit {
            LabeledContent("Sensitivity") {
                HStack {
                    Slider(value: $action.sensitivity, in: 0.2...2.0, step: 0.1).frame(width: 180)
                    Text(String(format: "%.1f×", action.sensitivity))
                        .monospacedDigit().frame(width: 36, alignment: .trailing)
                }
            }
        }
        if action.kind == .keys {
            LabeledContent(more) { KeyRecorder(combo: $action.clockwise) }
            LabeledContent(less) { KeyRecorder(combo: $action.counterClockwise) }
            Stepper("\(steps): \(action.stepsPerTurn)", value: $action.stepsPerTurn, in: 2...120, step: 2)
        }
    }
}

private struct ActionRow: View {
    let title: String
    @Binding var action: Action
    let allowInherit: Bool

    var body: some View {
        LabeledContent(title) {
            HStack {
                switch action.kind {
                case .keystroke:
                    KeyRecorder(combo: $action.key)
                case .shell:
                    TextField("", text: $action.text, prompt: Text("e.g. open -a Music"))
                        .textFieldStyle(.roundedBorder).frame(width: 190)
                case .showEmoji:
                    TextField("", text: $action.text, prompt: Text("🙂"))
                        .textFieldStyle(.roundedBorder).frame(width: 60)
                case .shortcut:
                    TextField("", text: $action.text, prompt: Text("Shortcut name"))
                        .textFieldStyle(.roundedBorder).frame(width: 190)
                default:
                    EmptyView()
                }
                Picker("", selection: $action.kind) {
                    ForEach(ActionKind.allCases.filter { $0 != .inherit || allowInherit }) {
                        Text($0.label).tag($0)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
            }
        }
    }
}

/// Click, then press a key combination. Escape cancels.
struct KeyRecorder: View {
    @Binding var combo: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press keys…" : (combo?.display ?? "Record")) {
            recording ? stop() : start()
        }
        .frame(minWidth: 90)
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.control, .option, .shift, .command])
            if !(event.keyCode == 53 && mods.isEmpty) { combo = KeyCombo(event: event) }
            stop()
            return nil
        }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recording = false
    }
}

private struct LivePanel: View {
    @ObservedObject var controller: Controller
    @ObservedObject var store: ConfigStore
    @ObservedObject var device: NuimoDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(device.state == .connected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(device.state.rawValue)
                if let b = device.battery { Text("· Battery \(b)%").foregroundStyle(.secondary) }
                if let f = device.firmware { Text("· Firmware \(f)").foregroundStyle(.secondary) }
                Spacer()
                Toggle("Show feedback on the Nuimo", isOn: $store.config.ledFeedback)
                    .toggleStyle(.checkbox)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if controller.events.isEmpty {
                        Text("Turn, press or swipe the Nuimo to see what it sends.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(controller.events.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 84)
        }
        .padding(12)
    }
}
