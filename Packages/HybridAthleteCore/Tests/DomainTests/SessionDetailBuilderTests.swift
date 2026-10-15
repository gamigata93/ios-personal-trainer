import Foundation
import Testing
@testable import Domain

/// Hand-calculated session details for the fixture plan, today Wed 28 Oct 2026.
struct SessionDetailBuilderTests {
    private typealias F = CalendarPlanFixture

    private func detail(_ month: Int, _ day: Int) throws -> SessionDetail {
        try #require(SessionDetailBuilder.build(plan: F.plan, runs: F.runs, sessionId: F.day(month, day).description, today: F.today))
    }

    @Test func the23rdIsCompletedShort() throws {
        let detail = try detail(10, 23)
        #expect(detail.status == .completed)
        #expect(detail.matchedRun?.distanceKm == 7.0)
        // 2520 / 7.0 = 360 s.
        #expect(detail.paceSecPerKm == 360)
        #expect(SessionFormat.paceText(secondsPerKm: 360) == "6:00 /km")
        #expect(SessionFormat.runDurationText(seconds: 2520) == "42:00")
        #expect(SessionFormat.distanceText(km: 7.0) == "7.0 km")
        #expect(SessionFormat.deltaKmText(try #require(detail.deltaKm)) == "\u{2212}3.0 km")
        #expect(detail.weekIndex == 2)
        #expect(detail.session.note != nil)
    }

    @Test func the26thIsSlightlyLonger() throws {
        let detail = try detail(10, 26)
        // 2046 / 6.2 = 330 s.
        #expect(detail.paceSecPerKm == 330)
        #expect(SessionFormat.paceText(secondsPerKm: 330) == "5:30 /km")
        #expect(SessionFormat.runDurationText(seconds: 2046) == "34:06")
        #expect(SessionFormat.deltaKmText(try #require(detail.deltaKm)) == "+0.2 km")
    }

    @Test func the14th() throws {
        let detail = try detail(10, 14)
        #expect(detail.paceSecPerKm == 360)
        #expect(SessionFormat.deltaKmText(try #require(detail.deltaKm)) == "+0.1 km")
        #expect(detail.session.estimatedMinutes == nil)
    }

    @Test func the21stIsNotRecorded() throws {
        let detail = try detail(10, 21)
        #expect(detail.status == .notRecorded)
        #expect(detail.matchedRun == nil)
        #expect(detail.deltaKm == nil)
        #expect(detail.paceSecPerKm == nil)
        #expect(abs(detail.requiredKm - 3.0) < 1e-9)
        #expect(SessionFormat.requiredRunText(requiredKm: detail.requiredKm) == "We look for a run of at least 3.0 km on the same day.")
    }

    @Test func todayIsWeekThreeOfTheBasePhase() throws {
        let detail = try detail(10, 28)
        #expect(detail.status == .today)
        #expect(detail.matchedRun == nil)
        #expect(detail.weekIndex == 3)
        #expect(detail.weeksTotal == 8)
        #expect(SessionFormat.weekPhaseLine(week: detail.weekIndex, of: detail.weeksTotal, phase: detail.phase) == "Week 3 of 8 · Base phase")
    }

    @Test func anUnknownIdIsNil() {
        #expect(SessionDetailBuilder.build(plan: F.plan, runs: F.runs, sessionId: "2026-10-27", today: F.today) == nil)
    }

    @Test func formattingEdges() {
        #expect(SessionFormat.runDurationText(seconds: 3600) == "1:00:00")
        #expect(SessionFormat.runDurationText(seconds: 3930) == "1:05:30")
        #expect(SessionFormat.runDurationText(seconds: 59) == "0:59")
        #expect(SessionFormat.paceText(secondsPerKm: 600) == "10:00 /km")
        #expect(SessionFormat.deltaKmText(0.04) == "As planned")
        #expect(SessionFormat.deltaKmText(-0.04) == "As planned")
        #expect(SessionFormat.deltaKmText(0.05) == "+0.1 km")
        #expect(SessionFormat.deltaKmText(-0.05) == "\u{2212}0.1 km")
        #expect(SessionType.allCases.map(SessionFormat.sessionTypeName) == ["Easy", "Tempo", "Threshold", "Intervals", "Long run"])
    }
}
