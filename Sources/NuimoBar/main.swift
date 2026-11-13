import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let controller = Controller()
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        controller.device.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &subscriptions)

        if CommandLine.arguments.contains("--settings") { openSettings() }
    }

    private func updateIcon() {
        let connected = controller.device.state == .connected
        let image = NSImage(systemSymbolName: connected ? "dial.medium.fill" : "dial.medium",
                            accessibilityDescription: "NuimoBar")
            ?? NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "NuimoBar")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = !connected
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let device = controller.device

        var status = device.state.rawValue
        if device.state == .connected, let b = device.battery { status += " · \(b)%" }
        menu.addItem(disabled(status))

        if !SystemActions.canPostEvents {
            menu.addItem(.separator())
            menu.addItem(disabled("Media keys, keystrokes and scrolling need Accessibility"))
            menu.addItem(item("Grant Accessibility Access…", #selector(grantAccessibility)))
        }

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        let calibrate = item("Calibrate Hover Sensor…", #selector(calibrateHover))
        if !device.canCalibrateHover { calibrate.action = nil; calibrate.isEnabled = false }
        menu.addItem(calibrate)
        let login = item("Open at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("Quit NuimoBar", #selector(quit), key: "q"))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func grantAccessibility() { SystemActions.requestAccessibility() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Open at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func calibrateHover() {
        let alert = NSAlert()
        alert.messageText = "Calibrate the hover sensor?"
        alert.informativeText = "Put the Nuimo where you normally use it and keep your hands and anything else clear of the space above it, then click Calibrate."
        alert.addButton(withTitle: "Calibrate")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        controller.device.calibrateHover()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Settings window

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(controller: controller, store: controller.store, device: controller.device)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "NuimoBar"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 800, height: 660))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
