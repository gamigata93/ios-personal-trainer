import Foundation
import Testing
import Application
import Domain

/// The worded calendar month and session detail for the fixture plan.
struct CalendarAndSessionDetailTests {
    private typealias F = CalendarPlanFixture

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// 09:00 UTC on `day`.
    private func clock(_ day: LocalDate) -> FakeClock {
        FakeClock(Self.utc.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 9)) ?? .distantPast)
    }

    private func runs(asOf: Date? = nil, locked: Bool = false) -> CompletedRunsResult {
        CompletedRunsResult(runs: F.runs, asOf: asOf, source: locked ? .locked : .fresh)
    }

    private let october = YearMonth(year: 2026, month: 10)

    // MARK: Calendar

    @Test func octoberOpensOnToday() {
        let use = GetCalendarMonth(clock: clock(F.today), calendar: Self.utc)
        #expect(use.defaultMonth(plan: F.plan) == october)
        let month = use.execute(plan: F.plan, runs: runs(), month: october, selected: nil)
        #expect(month.title == "October 2026")
        #expect(month.selectedDate == F.today)
        #expect(!month.canGoBack)
        #expect(month.canGoForward)
        #expect(month.cells.first { $0.date == F.today }?.accessibilityLabel == "Wednesday 28 October, Easy run, today")
        guard case .session(let card) = month.dayCard else {
            Issue.record("Expected a session card")
            return
        }
        #expect(card.name == "Easy run")
        #expect(card.statusText == "Today")
        #expect(month.lockedLine == nil)
    }

    @Test func aSelectionOutsideThePlanFallsBackToTheDefault() {
        let use = GetCalendarMonth(clock: clock(F.today), calendar: Self.utc)
        #expect(use.execute(plan: F.plan, runs: runs(), month: october, selected: F.day(10, 5)).selectedDate == F.today)
        #expect(use.execute(plan: F.plan, runs: runs(), month: october, selected: F.day(10, 30)).selectedDate == F.day(10, 30))
        #expect(use.execute(plan: F.plan, runs: runs(), month: october, selected: F.day(10, 31)).dayCard == .rest)
    }

    @Test func decemberIsLastAndRaceDayIsARaceCard() {
        let use = GetCalendarMonth(clock: clock(F.today), calendar: Self.utc)
        let december = use.execute(plan: F.plan, runs: runs(), month: YearMonth(year: 2026, month: 12), selected: F.raceDay)
        #expect(!december.canGoForward)
        #expect(december.dayCard == .race("10K race"))
    }

    @Test func aRequestedMonthIsClamped() {
        let use = GetCalendarMonth(clock: clock(F.today), calendar: Self.utc)
        #expect(use.defaultMonth(plan: F.plan, requested: YearMonth(year: 2027, month: 3)) == YearMonth(year: 2026, month: 12))
        #expect(use.defaultMonth(plan: F.plan, requested: YearMonth(year: 2026, month: 11)) == YearMonth(year: 2026, month: 11))
    }

    @Test func theLockedLine() {
        let now = clock(F.today).now()
        let use = GetCalendarMonth(clock: clock(F.today), calendar: Self.utc)
        let locked = use.execute(plan: F.plan, runs: runs(asOf: now.addingTimeInterval(-600), locked: true), month: october, selected: nil)
        #expect(locked.lockedLine == "Your phone is locked. Showing progress from 10 min ago.")
    }

    // MARK: Session detail

    private func detail(_ id: LocalDate) -> SessionDetailOverview? {
        GetSessionDetail(clock: clock(F.today), calendar: Self.utc).execute(plan: F.plan, runs: F.runs, sessionID: id.description)
    }

    @Test func aCompletedSessionShowsTheRun() throws {
        let detail = try #require(detail(F.day(10, 23)))
        #expect(detail.caption == "Session")
        #expect(detail.dateText == "Friday, 23 October")
        #expect(detail.typeName == "Long run")
        #expect(detail.statusText == "Completed")
        #expect(detail.result == .completed(distance: "7.0 km", duration: "42:00", pace: "6:00 /km", plannedLine: "Planned 10.0 km · \u{2212}3.0 km"))
        #expect(detail.note == "Rolling hills: keep the effort even on the climbs.")
        #expect(detail.segments.map(\.distance) == ["1.0 km", "8.0 km", nil])
        #expect(detail.segments[1].accessibilityLabel == "Segment 2, Long run, Steady pace, 8 kilometres")
        #expect(detail.distanceAccessibilityLabel == "Distance 10 kilometres")
    }

    @Test func the26thAndThe14th() throws {
        #expect(try #require(detail(F.day(10, 26))).result == .completed(distance: "6.2 km", duration: "34:06", pace: "5:30 /km", plannedLine: "Planned 6.0 km · +0.2 km"))
        let fourteenth = try #require(detail(F.day(10, 14)))
        #expect(fourteenth.estimatedTime == "\u{2014}")
        #expect(fourteenth.note == nil)
    }

    @Test func notRecordedExplainsTheRule() throws {
        let detail = try #require(detail(F.day(10, 21)))
        #expect(detail.result == .notRecorded(requiredRunText: "We look for a run of at least 3.0 km on the same day."))
    }

    @Test func todayAndUpcomingHaveNoResult() throws {
        let today = try #require(detail(F.today))
        #expect(today.caption == "Today's session")
        #expect(today.statusText == "Today")
        #expect(today.result == nil)
        #expect(today.weekPhaseLine == "Week 3 of 8 · Base phase")
        #expect(today.estimatedTime == "~39 min")
        let upcoming = try #require(detail(F.day(10, 30)))
        #expect(upcoming.caption == "Upcoming session")
        #expect(upcoming.result == nil)
    }

    @Test func anUnknownSessionIsNil() {
        #expect(detail(F.day(10, 27)) == nil)
    }
}
