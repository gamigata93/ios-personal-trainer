import Foundation
import Testing
import Domain

struct LocalDateTests {
    @Test func weekdaysAreMondayFirst() {
        #expect(LocalDate(year: 2026, month: 10, day: 9).weekday == .friday)
        #expect(LocalDate(year: 2026, month: 10, day: 12).weekday == .monday)
        #expect(LocalDate(year: 2026, month: 12, day: 6).weekday == .sunday)
        #expect(Weekday.allCases.map(\.letter).joined() == "MTWTFSS")
    }

    @Test func addingDaysCrossesMonthsYearsAndLeapDays() {
        #expect(LocalDate(year: 2026, month: 12, day: 30).adding(days: 3) == LocalDate(year: 2027, month: 1, day: 2))
        #expect(LocalDate(year: 2028, month: 2, day: 28).adding(days: 1) == LocalDate(year: 2028, month: 2, day: 29))
        #expect(LocalDate(year: 2026, month: 10, day: 12).days(to: LocalDate(year: 2026, month: 12, day: 6)) == 55)
    }

    @Test func codesAsAPlainDateString() throws {
        let date = LocalDate(year: 2026, month: 3, day: 7)
        let data = try JSONEncoder().encode([date])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2026-03-07\"]")
        #expect(try JSONDecoder().decode([LocalDate].self, from: data) == [date])
        #expect(LocalDate("2026-04-31") == nil)
    }

    @Test func comesFromTheCalendarDayNotUTC() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        // 20:00 UTC on 9 Oct is already 10 Oct in Tokyo.
        let instant = Date(timeIntervalSince1970: 1_791_576_000) // 2026-10-09T20:00:00Z
        #expect(LocalDate(instant, calendar: tokyo) == LocalDate(year: 2026, month: 10, day: 10))
    }

    @Test func planStartsOnTheFirstMondayOnOrAfterTomorrow() {
        #expect(PlanCalendar.planStart(today: LocalDate(year: 2026, month: 10, day: 9)) == LocalDate(year: 2026, month: 10, day: 12))
        // Sunday: tomorrow is Monday.
        #expect(PlanCalendar.planStart(today: LocalDate(year: 2026, month: 10, day: 11)) == LocalDate(year: 2026, month: 10, day: 12))
        // Monday: the next Monday, a week later.
        #expect(PlanCalendar.planStart(today: LocalDate(year: 2026, month: 10, day: 12)) == LocalDate(year: 2026, month: 10, day: 19))
    }

    @Test func weekCountRoundsUp() {
        let start = LocalDate(year: 2026, month: 10, day: 12)
        #expect(PlanCalendar.weekCount(from: start, to: LocalDate(year: 2026, month: 12, day: 6)) == 8) // 56 days
        #expect(PlanCalendar.weekCount(from: start, to: LocalDate(year: 2026, month: 12, day: 7)) == 9) // 57 days
    }

    @Test(arguments: [(5.0, PlanKind.fiveK), (6, .fiveK), (6.1, .tenK), (12, .tenK), (21.1, .halfMarathon), (25, .halfMarathon), (25.1, .marathon), (100, .marathon)])
    func planKindFromDistance(km: Double, kind: PlanKind) {
        #expect(PlanKind.from(distanceKm: km) == kind)
    }
}
