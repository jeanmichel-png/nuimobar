import AppKit
import ApplicationServices
import AudioToolbox
import CoreAudio
import Foundation

/// The Mac-side effects: volume, media keys, synthetic keystrokes and scrolling, scripts.
enum SystemActions {
    // MARK: Accessibility (needed to post keys, media keys and scroll events)

    static var canPostEvents: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: Volume (CoreAudio, so it is smooth and needs no permission)

    private static func outputDevice() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return st == noErr && id != 0 ? id : nil
    }

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    /// Output volume 0...1, or nil when the output device has no software volume (e.g. HDMI).
    static var volume: Float? {
        guard let dev = outputDevice(), AudioObjectHasProperty(dev, &volumeAddress) else { return nil }
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(dev, &volumeAddress, 0, nil, &size, &v) == noErr ? v : nil
    }

    @discardableResult
    static func setVolume(_ value: Float) -> Bool {
        guard let dev = outputDevice(), AudioObjectHasProperty(dev, &volumeAddress) else { return false }
        var v = Float32(max(0, min(1, value)))
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(dev, &volumeAddress, 0, nil, size, &v) == noErr
    }

    static var isMuted: Bool? {
        guard let dev = outputDevice(), AudioObjectHasProperty(dev, &muteAddress) else { return nil }
        var m = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &muteAddress, 0, nil, &size, &m) == noErr ? m != 0 : nil
    }

    /// Returns the new mute state, or nil if the device cannot be muted.
    static func toggleMute() -> Bool? {
        guard let dev = outputDevice(), let muted = isMuted else { return nil }
        var m: UInt32 = muted ? 0 : 1
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(dev, &muteAddress, 0, nil, size, &m) == noErr ? !muted : nil
    }

    // MARK: Media keys

    enum MediaKey: Int32 {
        case soundUp = 0, soundDown = 1, play = 16, next = 17, previous = 18
    }

    static func press(_ key: MediaKey) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key.rawValue << 16) | ((down ? 0xA : 0xB) << 8))
            let ev = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: data1, data2: -1)
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    // MARK: Mission Control / Exposé

    enum DockAction: String {
        case missionControl = "com.apple.expose.awake"
        case appWindows = "com.apple.expose.front.awake"
        case showDesktop = "com.apple.showdesktop.awake"

        /// Argument understood by the Mission Control app, used as a fallback.
        var launchArgument: String? {
            switch self {
            case .missionControl: return nil
            case .showDesktop: return "1"
            case .appWindows: return "2"
            }
        }
    }

    private typealias CoreDockSend = @convention(c) (CFString, UnsafeRawPointer?) -> Void

    private static let coreDockSend: CoreDockSend? = {
        let path = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        guard let handle = dlopen(path, RTLD_LAZY),
              let sym = dlsym(handle, "CoreDockSendNotification") else { return nil }
        return unsafeBitCast(sym, to: CoreDockSend.self)
    }()

    /// Asks the Dock to toggle a Mission Control view. Needs no permission.
    static func dock(_ action: DockAction) {
        if let send = coreDockSend {
            send(action.rawValue as CFString, nil)
        } else {
            launch("/System/Applications/Mission Control.app/Contents/MacOS/Mission Control",
                   action.launchArgument.map { [$0] } ?? [])
        }
    }

    // MARK: Keystrokes and scrolling

    static func send(_ combo: KeyCombo) {
        let src = CGEventSource(stateID: .hidSystemState)
        var flags = CGEventFlags()
        let m = combo.flags
        if m.contains(.command) { flags.insert(.maskCommand) }
        if m.contains(.shift) { flags.insert(.maskShift) }
        if m.contains(.option) { flags.insert(.maskAlternate) }
        if m.contains(.control) { flags.insert(.maskControl) }
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: combo.keyCode, keyDown: down) else { continue }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
    }

    static func scroll(vertical: Int32 = 0, horizontal: Int32 = 0) {
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                              wheel1: vertical, wheel2: horizontal, wheel3: 0) else { return }
        e.post(tap: .cghidEventTap)
    }

    // MARK: Scripts

    static func runShell(_ command: String) {
        guard !command.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        launch("/bin/zsh", ["-lc", command])
    }

    static func runShortcut(_ name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        launch("/usr/bin/shortcuts", ["run", name])
    }

    private static func launch(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
