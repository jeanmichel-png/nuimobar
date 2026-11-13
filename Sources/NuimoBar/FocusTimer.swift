import AppKit
import Foundation

/// A Pomodoro-style timer driven from the Nuimo.
///
/// Trigger it, turn the dial to choose minutes, press to start. The display
/// shows the minutes left once a minute and counts down the final minute in
/// seconds. A break follows automatically. Triggering it while it runs shows
/// the time left; triggering it again straight away stops it.
final class FocusTimer {
    enum Phase: String { case idle, setting, work, rest }

    private(set) var phase: Phase = .idle
    private(set) var minutes = 25
    var breakMinutes = 5

    /// Draws a frame on the Nuimo for a number of seconds.
    var show: ((LEDMatrix, Double) -> Void)?
    var onEvent: ((String) -> Void)?
    /// Called with the chosen length when a session starts, so it can be remembered.
    var onStart: ((Int) -> Void)?
    /// Seconds per minute; only changed by the self-test to run quickly.
    var secondsPerMinute: TimeInterval = 60

    private var endDate = Date.distantPast
    private var ticker: Timer?
    private var settingTimeout: Timer?
    private var lastPeek = Date.distantPast
    private var dialAccumulator = 0.0
    private var lastShownSecond = -1

    /// While choosing a length, the dial and press belong to the timer.
    var isCapturingInput: Bool { phase == .setting }

    var secondsLeft: Int {
        phase == .work || phase == .rest ? max(0, Int(endDate.timeIntervalSinceNow.rounded(.up))) : 0
    }

    /// One line for the menu, or nil when idle.
    var status: String? {
        switch phase {
        case .idle: return nil
        case .setting: return "Focus timer: choosing \(minutes) min"
        case .work, .rest:
            let s = Int((Double(secondsLeft) * 60 / secondsPerMinute).rounded(.up))
            let label = phase == .work ? "Focus" : "Break"
            return s > 60 ? "\(label): \((s + 59) / 60) min left" : "\(label): \(s) s left"
        }
    }

    // MARK: Input

    /// The gesture mapped to "Focus timer".
    func trigger(defaultMinutes: Int) {
        switch phase {
        case .idle:
            minutes = max(1, min(99, defaultMinutes))
            phase = .setting
            dialAccumulator = 0
            showSetting()
            onEvent?("Focus timer: turn to set, press to start")
        case .setting:
            cancelSetting()
        case .work, .rest:
            if Date().timeIntervalSince(lastPeek) < 3 {
                stop()
            } else {
                lastPeek = Date()
                showRemaining(seconds: 3)
                onEvent?(status ?? "")
            }
        }
    }

    /// Dial movement while choosing a length; a full turn is 30 minutes.
    func rotate(turns: Double) {
        guard phase == .setting else { return }
        dialAccumulator += turns * 30
        let steps = Int(dialAccumulator.rounded(.towardZero))
        guard steps != 0 else { return }
        dialAccumulator -= Double(steps)
        minutes = max(1, min(99, minutes + steps))
        showSetting()
    }

    /// Returns true if the press was used to start the timer.
    func press() -> Bool {
        guard phase == .setting else { return false }
        startWork(minutes: minutes)
        return true
    }

    func startWork(minutes m: Int) {
        minutes = max(1, min(99, m))
        settingTimeout?.invalidate()
        onStart?(minutes)
        begin(.work, minutes: minutes)
        onEvent?("Focus started: \(minutes) min")
    }

    func stop() {
        guard phase != .idle else { return }
        ticker?.invalidate()
        settingTimeout?.invalidate()
        phase = .idle
        show?(LEDMatrix(glyph: "❌"), 1.5)
        onEvent?("Focus timer stopped")
    }

    // MARK: Internals

    private func showSetting() {
        show?(.number(minutes), 8)
        settingTimeout?.invalidate()
        settingTimeout = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            self?.cancelSetting()
        }
    }

    private func cancelSetting() {
        guard phase == .setting else { return }
        settingTimeout?.invalidate()
        phase = .idle
        show?(.hoverOff, 0.8)
        onEvent?("Focus timer cancelled")
    }

    private func begin(_ newPhase: Phase, minutes m: Int) {
        phase = newPhase
        endDate = Date().addingTimeInterval(Double(m) * secondsPerMinute)
        lastShownSecond = -1
        show?(.number(m), 3)
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        let left = secondsLeft
        guard left > 0 else { finish(); return }
        guard left != lastShownSecond else { return }
        lastShownSecond = left
        let perMinute = Int(secondsPerMinute)
        if left <= min(60, perMinute) {
            show?(.number(left), 1.5)                     // final minute: count down in seconds
        } else if left % perMinute == 0 {
            show?(.number(left / perMinute), 3)           // otherwise a glance once a minute
        }
    }

    private func showRemaining(seconds: Double) {
        let left = secondsLeft
        let perMinute = Int(secondsPerMinute)
        show?(.number(left <= min(60, perMinute) ? left : (left + perMinute - 1) / perMinute), seconds)
    }

    private func finish() {
        ticker?.invalidate()
        NSSound(named: "Glass")?.play()
        if phase == .work, breakMinutes > 0 {
            onEvent?("Focus finished. Break: \(breakMinutes) min")
            begin(.rest, minutes: breakMinutes)
            show?(LEDMatrix(glyph: "☕"), 6)
        } else {
            phase = .idle
            show?(LEDMatrix(glyph: "🔔"), 6)
            onEvent?("Break finished")
        }
    }
}

extension LEDMatrix {
    private static let digits: [[String]] = [
        [".##.", "#..#", "#..#", "#..#", "#..#", "#..#", ".##."],
        ["..#.", ".##.", "..#.", "..#.", "..#.", "..#.", ".###"],
        [".##.", "#..#", "...#", "..#.", ".#..", "#...", "####"],
        ["###.", "...#", "...#", ".##.", "...#", "...#", "###."],
        ["#..#", "#..#", "#..#", "####", "...#", "...#", "...#"],
        ["####", "#...", "###.", "...#", "...#", "#..#", ".##."],
        [".##.", "#...", "#...", "###.", "#..#", "#..#", ".##."],
        ["####", "...#", "..#.", "..#.", ".#..", ".#..", ".#.."],
        [".##.", "#..#", "#..#", ".##.", "#..#", "#..#", ".##."],
        [".##.", "#..#", "#..#", ".###", "...#", "...#", ".##."],
    ]

    /// A number from 0 to 99 in 4×7 digits.
    static func number(_ value: Int) -> LEDMatrix {
        let n = max(0, min(99, value))
        var m = LEDMatrix()
        func draw(_ digit: Int, atColumn x: Int) {
            for (r, row) in digits[digit].enumerated() {
                for (c, ch) in row.enumerated() where ch == "#" { m.bits[(r + 1) * 9 + x + c] = true }
            }
        }
        if n < 10 {
            draw(n, atColumn: 2)
        } else {
            draw(n / 10, atColumn: 0)
            draw(n % 10, atColumn: 5)
        }
        return m
    }
}
