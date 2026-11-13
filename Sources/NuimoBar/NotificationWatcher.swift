import AppKit
import ApplicationServices

/// Spots notification banners as they appear on screen.
///
/// macOS has no public API for seeing other apps' notifications, so this reads
/// the Notification Centre's banner windows through Accessibility (the same
/// permission the app already needs for keystrokes). It only sees banners that
/// are actually shown, so nothing arrives while a Focus mode is hiding them.
final class NotificationWatcher {
    struct Banner: Hashable {
        /// Unique per notification, so identical messages still count separately.
        var id: String
        var app: String
        var title: String
        var body: String
    }

    var onBanner: ((Banner) -> Void)?
    /// Receives a dump of the banner tree whenever it changes, for diagnostics.
    var onDebug: ((String) -> Void)?

    private var timer: Timer?
    private var visible = Set<String>()
    private var lastDump = ""

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        guard AXIsProcessTrusted(),
              let nc = NSRunningApplication.runningApplications(
                  withBundleIdentifier: "com.apple.notificationcenterui").first else { return }
        let app = AXUIElementCreateApplication(nc.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.4)
        let windows = (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []

        var found = Set<Banner>()
        var dump = ""
        for w in windows { walk(w, depth: 0, into: &found, dump: &dump) }

        if dump != lastDump {
            lastDump = dump
            if !dump.isEmpty { onDebug?(dump) }
        }
        for banner in found where !visible.contains(banner.id) { onBanner?(banner) }
        visible = Set(found.map(\.id))
    }

    private func attribute(_ e: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
    }

    private func string(_ e: AXUIElement, _ name: String) -> String {
        (attribute(e, name) as? String) ?? ""
    }

    private func walk(_ e: AXUIElement, depth: Int, into found: inout Set<Banner>, dump: inout String) {
        guard depth < 12 else { return }
        let role = string(e, kAXRoleAttribute)
        let subrole = string(e, kAXSubroleAttribute)
        let description = string(e, kAXDescriptionAttribute)
        let title = string(e, kAXTitleAttribute)
        let value = (attribute(e, kAXValueAttribute) as? String) ?? ""
        let identifier = string(e, "AXIdentifier")
        dump += String(repeating: "  ", count: depth)
            + "\(role)/\(subrole) id=\(identifier) title=\(title) desc=\(description) value=\(value)\n"

        if subrole == "AXNotificationCenterBanner" || subrole == "AXNotificationCenterAlert" {
            found.insert(banner(e, identifier: identifier, description: description))
        }
        for child in (attribute(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            walk(child, depth: depth + 1, into: &found, dump: &dump)
        }
    }

    /// A banner's description reads "App, Title, Body"; its title and body are
    /// also child labels, which lets the app name be separated out reliably
    /// even when any of the three contains a comma.
    private func banner(_ e: AXUIElement, identifier: String, description: String) -> Banner {
        var title = "", body = ""
        for child in (attribute(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            let value = (attribute(child, kAXValueAttribute) as? String) ?? ""
            switch string(child, "AXIdentifier") {
            case "title": title = value
            case "body": body = value
            default: break
            }
        }
        var app = description
        if !title.isEmpty, let r = description.range(of: ", " + title) {
            app = String(description[..<r.lowerBound])
        } else if let r = description.range(of: ", ") {
            app = String(description[..<r.lowerBound])
        }
        return Banner(id: identifier.isEmpty ? description : identifier, app: app, title: title, body: body)
    }
}
