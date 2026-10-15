import Foundation
import Testing
@testable import Domain

/// Hand-checked months for the fixture plan with today Wed 28 Oct 2026.
struct CalendarMonthBuilderTests {
    private typealias F = CalendarPlanFixture

    private func month(_ number: Int, today: LocalDate = F.today) -> CalendarMonth {
        CalendarMonthBuilder.month(YearMonth(year: 2026, month: number), plan: F.plan, runs: F.runs, today: today)
    }

    @Test func theMonthsAvailable() {
        #expect(CalendarRange.months(of: F.plan).map(\.description) == ["2026-10", "2026-11", "2026-12"])
        #expect(CalendarRange.clamp(YearMonth(year: 2026, month: 9), to: F.plan) == YearMonth(year: 2026, month: 10))
        #expect(CalendarRange.clamp(YearMonth(year: 2027, month: 1), to: F.plan) == YearMonth(year: 2026, month: 12))
    }

    @Test func october() {
        let october = month(10)
        #expect(october.title == "October 2026")
        #expect(october.weekdayLabels == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(october.leadingBlanks == 3)
        #expect(october.cells.count == 31)
        #expect(october.trailingBlanks == 1)
        #expect(october.slotCount == 35)
        #expect(october.cells.filter { $0.kind == .beforePlan }.map(\.date.day) == Array(1...11))
        #expect(october.cells.filter { $0.kind == .inPlan }.map(\.date.day) == Array(12...31))
        #expect(october.isFirstMonth)
        #expect(!october.isLastMonth)
    }

    @Test func november() {
        let november = month(11)
        #expect(november.leadingBlanks == 6)
        #expect(november.cells.count == 30)
        #expect(november.trailingBlanks == 6)
        #expect(november.slotCount == 42)
        #expect(november.cells.allSatisfy { $0.kind == .inPlan })
        #expect(november.cells.filter { $0.session != nil }.count == 13)
        #expect(!november.isFirstMonth && !november.isLastMonth)
    }

    @Test func december() {
        let december = month(12)
        #expect(december.leadingBlanks == 1)
        #expect(december.cells.count == 31)
        #expect(december.slotCount == 35)
        #expect(december.cells.filter { $0.kind == .inPlan }.map(\.date.day) == Array(1...6))
        #expect(december.cells.filter { $0.kind == .afterRace }.map(\.date.day) == Array(7...31))
        #expect(december.cells.filter(\.isRaceDay).map(\.date.day) == [6])
        #expect(december.cells.filter { $0.session != nil }.map(\.date.day) == [2, 4])
        #expect(december.isLastMonth)
    }

    @Test func octoberStatuses() {
        let cells = month(10).cells
        func days(_ status: SessionStatus) -> [Int] {
            cells.filter { $0.status == status }.map(\.date.day)
        }
        #expect(cells.filter { $0.session != nil }.map(\.date.day) == [12, 14, 16, 19, 21, 23, 26, 28, 30])
        #expect(days(.completed) == [12, 14, 16, 19, 23, 26])
        #expect(days(.notRecorded) == [21])
        #expect(days(.today) == [28])
        #expect(days(.upcoming) == [30])
    }

    @Test func aRunOfSixtyPercentOrMoreCompletes() {
        // 23 Oct: planned 10.0, run 7.0 >= 0.6 x 10.0 = 6.0.
        let cell = month(10).cell(on: F.day(10, 23))
        #expect(cell?.status == .completed)
        #expect(month(10).cell(on: F.day(10, 21))?.status == .notRecorded)
    }

    @Test func defaultMonthAndSelection() {
        #expect(CalendarMonthBuilder.defaultMonth(plan: F.plan, today: F.today) == YearMonth(year: 2026, month: 10))
        #expect(CalendarMonthBuilder.defaultSelection(in: month(10), plan: F.plan, today: F.today) == F.day(10, 28))
        #expect(CalendarMonthBuilder.defaultSelection(in: month(11), plan: F.plan, today: F.today) == F.day(11, 2))
        #expect(CalendarMonthBuilder.defaultSelection(in: month(12), plan: F.plan, today: F.today) == F.day(12, 2))
    }

    @Test func beforeThePlanAndAfterTheRace() {
        let before = F.day(10, 10)
        #expect(CalendarMonthBuilder.defaultMonth(plan: F.plan, today: before) == YearMonth(year: 2026, month: 10))
        #expect(CalendarMonthBuilder.defaultSelection(in: month(10, today: before), plan: F.plan, today: before) == F.day(10, 12))

        let after = F.day(12, 7)
        #expect(CalendarMonthBuilder.defaultMonth(plan: F.plan, today: after) == YearMonth(year: 2026, month: 12))
        #expect(CalendarMonthBuilder.defaultSelection(in: month(12, today: after), plan: F.plan, today: after) == F.raceDay)
    }

    @Test func cellsOutsideThePlanAreNotSelectable() {
        let october = month(10)
        #expect(october.cell(on: F.day(10, 11))?.isSelectable == false)
        #expect(october.cell(on: F.day(10, 12))?.isSelectable == true)
        #expect(month(12).cell(on: F.day(12, 7))?.isSelectable == false)
    }

    @Test func accessibilityLabels() throws {
        let october = month(10)
        #expect(CalendarFormat.accessibilityLabel(try #require(october.cell(on: F.day(10, 28)))) == "Wednesday 28 October, Easy run, today")
        #expect(CalendarFormat.accessibilityLabel(try #require(october.cell(on: F.day(10, 21)))) == "Wednesday 21 October, Easy run, not recorded")
        #expect(CalendarFormat.accessibilityLabel(try #require(october.cell(on: F.day(10, 10)))) == "Saturday 10 October, outside the plan")
    }

    @Test func yearMonthArithmetic() {
        let december = YearMonth(year: 2026, month: 12)
        #expect(december.adding(months: 1) == YearMonth(year: 2027, month: 1))
        #expect(YearMonth(year: 2027, month: 1).adding(months: -1) == december)
        #expect(YearMonth("2026-11") == YearMonth(year: 2026, month: 11))
        #expect(YearMonth("2026-13") == nil)
        #expect(YearMonth(year: 2028, month: 2).dayCount == 29)
    }
}
