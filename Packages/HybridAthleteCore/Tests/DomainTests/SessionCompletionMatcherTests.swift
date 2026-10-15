import Foundation
import Testing
@testable import Domain

struct SessionCompletionMatcherTests {
    private typealias F = PlanFixtures
    private let session = F.session(F.day(10, 14), .tempo, km: 10)

    @Test func exactlySixtyPercentCounts() {
        let run = F.run(F.day(10, 14), km: 6.0)
        #expect(SessionCompletionMatcher.match(sessions: [session], runs: [run])[session.id] == run)
    }

    @Test func justUnderSixtyPercentDoesNot() {
        let matches = SessionCompletionMatcher.match(sessions: [session], runs: [F.run(F.day(10, 14), km: 5.99)])
        #expect(matches.isEmpty)
    }

    @Test func aRunOnTheDayBeforeOrAfterDoesNotMatch() {
        let runs = [F.run(F.day(10, 13), km: 10), F.run(F.day(10, 15), km: 10)]
        #expect(SessionCompletionMatcher.match(sessions: [session], runs: runs).isEmpty)
    }

    @Test func twoRunsOnOneDayTakeTheLarger() {
        let small = F.run(F.day(10, 14), km: 6.5, id: "a")
        let large = F.run(F.day(10, 14), km: 8.0, id: "b")
        #expect(SessionCompletionMatcher.match(sessions: [session], runs: [small, large])[session.id] == large)
    }

    @Test func oneRunNeverMatchesTwoSessions() {
        // Two sessions on one day (not something a valid plan holds) share the only run at most once.
        let morning = F.session(F.day(10, 14), km: 5)
        let evening = PlannedSession(date: F.day(10, 14), type: .easy, name: "Second", distanceKm: 5, estimatedMinutes: nil, effort: "", segments: [], note: nil)
        let run = F.run(F.day(10, 14), km: 5)
        let matches = SessionCompletionMatcher.match(sessions: [morning, evening], runs: [run])
        #expect(matches.values.filter { $0 == run }.count == 1)
    }

    @Test func aRunOnARestDayIsIgnored() {
        let matches = SessionCompletionMatcher.match(sessions: [session], runs: [F.run(F.day(10, 16), km: 12)])
        #expect(matches.isEmpty)
    }

    @Test func statusComesFromTheMatchThenTheDate() {
        let today = F.day(10, 14)
        #expect(SessionStatus.of(date: today, isMatched: true, today: today) == .completed)
        #expect(SessionStatus.of(date: F.day(10, 13), isMatched: false, today: today) == .notRecorded)
        #expect(SessionStatus.of(date: today, isMatched: false, today: today) == .today)
        #expect(SessionStatus.of(date: F.day(10, 15), isMatched: false, today: today) == .upcoming)
    }

    // MARK: Time zones (Europe/Sofia is UTC+3 in October)

    private var sofia: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Sofia") ?? .gmt
        return calendar
    }

    @Test func aRunAt2330LocalBelongsToThatDay() throws {
        let start = try #require(ISO8601DateFormatter().date(from: "2026-10-12T20:30:00Z"))
        #expect(LocalDate(date: start, calendar: sofia) == F.day(10, 12))
    }

    @Test func aRunAt0100LocalBelongsToTheNextDay() throws {
        let start = try #require(ISO8601DateFormatter().date(from: "2026-10-12T22:00:00Z"))
        #expect(LocalDate(date: start, calendar: sofia) == F.day(10, 13))
    }
}
