import Foundation
import Testing
import Domain

struct UpdatedLabelTests {
    /// Fri 9 Oct 2026, 10:00 UTC.
    private let now = UTC.date(2026, 10, 9, hour: 10)

    private func label(_ then: Date) -> String {
        UpdatedLabel.text(now: now, then: then, calendar: UTC.calendar)
    }

    @Test func underAMinuteIsJustNow() {
        #expect(label(now.addingTimeInterval(-30)) == "just now")
    }

    @Test func minutesUnderAnHour() {
        #expect(label(now.addingTimeInterval(-5 * 60)) == "5 min ago")
        #expect(label(now.addingTimeInterval(-59 * 60)) == "59 min ago")
    }

    @Test func earlierTodayShowsTheTime() {
        // 08:12 the same day, 1 h 48 min earlier.
        let then = UTC.calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 8, minute: 12)) ?? now
        #expect(label(then) == "today 08:12")
    }

    @Test func yesterdayShowsTheTime() {
        let then = UTC.calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 18, minute: 40)) ?? now
        #expect(label(then) == "yesterday 18:40")
    }

    @Test func olderShowsTheDate() {
        let then = UTC.calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 7)) ?? now
        #expect(label(then) == "3 Oct")
    }
}
