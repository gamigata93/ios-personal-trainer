import Foundation
import Testing
import Domain

struct SuggestedRaceDateTests {
    private let friday = UTC.date(2026, 10, 9) // Fri 9 Oct 2026

    private func day(_ plan: PlanKind, from now: Date) throws -> DateComponents {
        let date = try #require(SuggestedRaceDate.date(from: now, plan: plan, calendar: UTC.calendar))
        return UTC.calendar.dateComponents([.year, .month, .day, .weekday], from: date)
    }

    @Test func movesToTheNextSundayAfterThePlan() throws {
        // +6 weeks = Fri 20 Nov -> Sun 22 Nov. +8 = Fri 4 Dec -> Sun 6 Dec.
        // +12 = Fri 1 Jan 2027 -> Sun 3 Jan. +16 = Fri 29 Jan -> Sun 31 Jan.
        let expected: [(PlanKind, Int, Int, Int)] = [
            (.fiveK, 2026, 11, 22), (.tenK, 2026, 12, 6), (.halfMarathon, 2027, 1, 3), (.marathon, 2027, 1, 31),
        ]
        for (plan, year, month, dayOfMonth) in expected {
            let components = try day(plan, from: friday)
            #expect(components.year == year)
            #expect(components.month == month)
            #expect(components.day == dayOfMonth)
            #expect(components.weekday == 1)
        }
    }

    @Test func aSundayPlusWholeWeeksStaysOnThatSunday() throws {
        let sunday = UTC.date(2026, 10, 11)
        let components = try day(.fiveK, from: sunday) // +42 days = Sun 22 Nov
        #expect(components.month == 11)
        #expect(components.day == 22)
    }
}
