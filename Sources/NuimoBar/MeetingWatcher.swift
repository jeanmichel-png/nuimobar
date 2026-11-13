import AppKit
import EventKit
import Foundation

/// Counts down to the next calendar event on the Nuimo.
///
/// Reads the calendars set up in the macOS Calendar app. In the run-up to an
/// event it shows the minutes left once a minute, then a bell at the start.
final class MeetingWatcher {
    private let store = EKEventStore()
    private var timer: Timer?
    private var lastShown: (id: String, minute: Int)?

    var isEnabled: () -> Bool = { true }
    var leadMinutes: () -> Int = { 10 }
    var show: ((LEDMatrix, Double) -> Void)?
    var onEvent: ((String) -> Void)?

    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func start() {
        requestAccess()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.check() }
    }

    func requestAccess() {
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else { return }
        store.requestFullAccessToEvents { _, _ in }
    }

    /// Timed events that have not been declined or cancelled, soonest first.
    private func events(from: Date, to: Date) -> [EKEvent] {
        guard hasAccess else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate)
            .filter { e in
                guard !e.isAllDay, e.status != .canceled else { return false }
                let me = e.attendees?.first(where: \.isCurrentUser)
                return me?.participantStatus != .declined
            }
            .sorted { $0.startDate < $1.startDate }
    }

    /// The next event that has not started yet, within the lead time.
    private var upcoming: EKEvent? {
        let now = Date()
        return events(from: now, to: now.addingTimeInterval(Double(leadMinutes()) * 60 + 60))
            .first { $0.startDate > now.addingTimeInterval(-20) }
    }

    /// One line for the menu, or nil when nothing is coming up within the hour.
    var status: String? {
        let now = Date()
        guard let e = events(from: now, to: now.addingTimeInterval(3600)).first(where: { $0.startDate > now }) else {
            return nil
        }
        let mins = max(1, Int((e.startDate.timeIntervalSince(now) / 60).rounded(.up)))
        return "Next: \(e.title ?? "Event") in \(mins) min"
    }

    private func check() {
        guard isEnabled(), let e = upcoming else { return }
        let id = e.eventIdentifier ?? e.title ?? ""
        let seconds = e.startDate.timeIntervalSinceNow
        let minute = seconds <= 0 ? 0 : Int((seconds / 60).rounded(.up))
        if let last = lastShown, last.id == id, last.minute == minute { return }
        lastShown = (id, minute)
        if minute == 0 {
            show?(LEDMatrix(glyph: "🔔"), 10)
            onEvent?("Meeting starting: \(e.title ?? "Event")")
        } else if minute <= leadMinutes() {
            show?(.number(minute), 5)
            onEvent?("\(e.title ?? "Event") in \(minute) min")
        }
    }

    // MARK: Joining

    private static let linkPattern = try! NSRegularExpression(
        pattern: #"https://[^\s<>"]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com|whereby\.com)[^\s<>"]*"#)

    private func joinURL(for e: EKEvent) -> URL? {
        for text in [e.location, e.notes, e.url?.absoluteString].compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            if let m = Self.linkPattern.firstMatch(in: text, range: range), let r = Range(m.range, in: text) {
                return URL(string: String(text[r]))
            }
        }
        return e.url
    }

    /// Opens the video link of the meeting that is about to start or has just started.
    @discardableResult
    func joinNext() -> Bool {
        let now = Date()
        let candidates = events(from: now.addingTimeInterval(-30 * 60), to: now.addingTimeInterval(15 * 60))
            .filter { $0.endDate > now }
        for e in candidates {
            if let url = joinURL(for: e) {
                NSWorkspace.shared.open(url)
                onEvent?("Joining \(e.title ?? "meeting")")
                return true
            }
        }
        onEvent?(hasAccess ? "No meeting link found" : "Calendar access not granted")
        return false
    }
}
