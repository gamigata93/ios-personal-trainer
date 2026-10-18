import Foundation
import Testing
import Application
import Domain
@testable import Infrastructure

/// The worked scenario: the `-seedPlan` plan (10 km race on Sun 6 Dec 2026,
/// Mon/Wed/Fri, 8 weeks from Mon 12 Oct) seen on different days.
struct HomeOverviewScenarioTests {
    private struct FixedClock: Clock {
        let date: Date
        func now() -> Date { date }
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private let plan = SeedPlan.plan(createdAt: Date(timeIntervalSince1970: 0))

    private func day(_ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: 2026, month: month, day: day)
    }

    /// 09:00 UTC on the given day.
    private func overview(
        today: LocalDate,
        runs: [CompletedRun] = [],
        strength: [CompletedStrength] = [],
        weekOffset: Int = 0,
        selected: LocalDate? = nil,
        source: CompletedRunsResult.Source = .fresh
    ) -> HomeOverview {
        let midnight = today.date(in: calendar) ?? .distantPast
        let use = GetHomeOverview(
            clock: FixedClock(date: midnight.addingTimeInterval(9 * 3_600)),
            calendar: calendar,
            sleepOverview: GetSleepOverview(calendar: calendar, locale: Locale(identifier: "en_GB")),
            recoveryOverview: GetRecoveryOverview()
        )
        return use.execute(
            plan: plan,
            runs: CompletedRunsResult(runs: runs, strength: strength, asOf: midnight, source: source),
            weekOffset: weekOffset,
            selectedDate: selected
        )
    }

    private func run(_ month: Int, _ dayOfMonth: Int, _ km: Double) -> CompletedRun {
        CompletedRun(id: "r-\(month)-\(dayOfMonth)", localDate: day(month, dayOfMonth), distanceKm: km, durationSeconds: km * 337)
    }

    /// No run on 21 Oct and none today. 23 Oct: 7.0 >= 0.6 x 8.0 = 4.8, so completed.
    private var scenarioRuns: [CompletedRun] {
        [run(10, 12, 5.0), run(10, 14, 4.6), run(10, 16, 9.2), run(10, 19, 5.5), run(10, 23, 7.0), run(10, 26, 6.2)]
    }

    /// Strength workouts on the seed plan's two strength days before the 28th.
    private var scenarioStrength: [CompletedStrength] {
        [14, 21].map { CompletedStrength(id: "s-\($0)", localDate: day(10, $0), durationSeconds: 32 * 60, kind: .traditionalStrength) }
    }

    @Test func theSeedPlanHasStrengthOnItsEasyWednesdays() {
        // Mon tempo, Wed easy, Fri long: Wednesday is the only allowed day; race week has none.
        #expect(plan.strengthSessions.map { "\($0.date) \($0.focus.rawValue) \($0.variant.rawValue)" } == [
            "2026-10-14 lowerBody A", "2026-10-21 calvesFeet A", "2026-10-28 lowerBody B",
            "2026-11-04 fullBody A", "2026-11-11 calvesFeet B", "2026-11-18 fullBody B", "2026-11-25 lowerBody A",
        ])
    }

    @Test func theSeedPlanHasTheExpectedSessionsBeforeTheTwentyEighth() {
        let before = plan.sessions.filter { $0.date <= day(10, 28) }.map { "\($0.id) \($0.distanceKm)" }
        // The template's actual numbers (the spec's hand list differs, the outcome does not).
        #expect(before == [
            "2026-10-12 5.0", "2026-10-14 6.0", "2026-10-16 7.5", "2026-10-19 5.5",
            "2026-10-21 7.0", "2026-10-23 8.0", "2026-10-26 6.0", "2026-10-28 7.5",
        ])
        #expect(plan.weeks.count == 8)
    }

    // MARK: Wed 28 Oct

    @Test func midPlanPlanCard() {
        let home = overview(today: day(10, 28), runs: scenarioRuns, strength: scenarioStrength)
        #expect(home.header.dateCaption == "Wednesday, 28 October")
        #expect(home.header.greeting == "Good morning")
        #expect(home.planCard.raceTitle == "10K race")
        // 28 Oct to 28 Nov is 31 days, then 8 more to 6 Dec.
        #expect(home.planCard.countdownValue == "39")
        #expect(home.planCard.countdownUnit == "days to go")
        #expect(home.planCard.countdownAccessibilityLabel == "39 days to go")
        #expect(home.planCard.pill?.text == "Base phase")
        #expect(home.planCard.pill?.isMuted == false)
        #expect(home.planCard.weekCaption == "Week 3 of 8")
        // Runs 6 of 7 plus strength 2 of 2: 8 of 9 is 88.9%, shown as 89%.
        #expect(home.dueCount == 9)
        #expect(home.completedCount == 8)
        #expect(home.planCard.ringValue == "89%")
        #expect(home.planCard.ringCaption == "on plan")
        #expect(home.planCard.ringAccessibilityLabel == "Plan adherence 89 percent")
        // Without the strength workouts the two strength sessions are due and not done: 6 of 9.
        #expect(overview(today: day(10, 28), runs: scenarioRuns).planCard.ringValue == "67%")
        #expect(home.lockedLine == nil)
    }

    @Test func midPlanWeekStrip() throws {
        let home = overview(today: day(10, 28), runs: scenarioRuns)
        let week = try #require(home.week)
        #expect(week.index == 3)
        #expect(week.rangeLabel == "26 Oct - 1 Nov")
        #expect(week.days.map(\.dayNumber) == ["26", "27", "28", "29", "30", "31", "1"])
        #expect(week.days.map(\.status) == [.completed, nil, .today, nil, .upcoming, nil, nil])
        #expect(week.days[2].isSelected)
        #expect(week.days[2].accessibilityLabel == "Wednesday 28 October, Easy run, today, plus Strength: Lower body B, today")
        #expect(week.days.map(\.strengthStatus) == [nil, nil, .today, nil, nil, nil, nil])
        #expect(week.days[1].accessibilityLabel == "Tuesday 27 October, Rest day")
    }

    @Test func midPlanSelectionAndUpNext() {
        let home = overview(today: day(10, 28), runs: scenarioRuns)
        #expect(home.selectedDate == day(10, 28))
        guard case .session(let card) = home.selectedCard else {
            Issue.record("Expected a session card")
            return
        }
        #expect(card.name == "Easy run")
        #expect(card.status == .today)
        #expect(card.statusText == "Today")
        #expect(card.meta == "7.5 km · ~40 min")
        #expect(home.upNext?.caption == "Up next · Fri 30 Oct")
        #expect(home.upNext?.name == "Long run")
    }

    @Test func tappingFridayShowsTheUpcomingLongRun() {
        let home = overview(today: day(10, 28), runs: scenarioRuns, selected: day(10, 30))
        guard case .session(let card) = home.selectedCard else {
            Issue.record("Expected a session card")
            return
        }
        #expect(card.name == "Long run")
        #expect(card.statusText == "Upcoming")
    }

    @Test func notRecordedAndCompletedInAnEarlierWeek() throws {
        let week = try #require(overview(today: day(10, 28), runs: scenarioRuns, weekOffset: -1).week)
        #expect(week.index == 2)
        // 19 Oct done, 21 Oct no run, 23 Oct 7.0 km of 8.0 counts.
        #expect(week.days.compactMap(\.status) == [.completed, .notRecorded, .completed])
    }

    @Test func fakeRunsGiveTheSameAdherence() async throws {
        // -fakeRuns: 95% of every session before today, except the 5th (21 Oct).
        let summaries = FakeRunsHealthDataSource.runs(for: plan, today: day(10, 28), calendar: calendar)
        #expect(summaries.count == 6)
        #expect(!summaries.contains { $0.id == "fake-2026-10-21" })
        let runs = summaries.map {
            CompletedRun(id: $0.id, localDate: LocalDate(date: $0.startDate, calendar: calendar), distanceKm: $0.distanceMeters / 1_000, durationSeconds: $0.durationSeconds)
        }
        // -fakeRuns also completes every strength session before today (14 and 21 Oct).
        let plan = plan
        let source = FakeRunsHealthDataSource(
            base: InMemoryHealthDataSource(clock: FixedClock(date: .distantPast)), activePlan: { plan },
            clock: FixedClock(date: (day(10, 28).date(in: calendar) ?? .distantPast).addingTimeInterval(9 * 3_600)), calendar: calendar
        )
        let strength = try await source.strengthWorkouts(from: day(10, 12), to: day(10, 28)).map {
            CompletedStrength(id: $0.id, localDate: LocalDate(date: $0.startDate, calendar: calendar), durationSeconds: $0.durationSeconds, kind: $0.kind)
        }
        #expect(strength.map(\.localDate) == [day(10, 14), day(10, 21)])
        #expect(overview(today: day(10, 28), runs: runs, strength: strength).planCard.ringValue == "89%")
    }

    @Test func lockedShowsTheCacheTime() {
        let home = overview(today: day(10, 28), runs: scenarioRuns, source: .locked)
        #expect(home.lockedLine == "Your phone is locked. Showing progress from today 00:00.")
    }

    // MARK: Week navigation

    @Test func weekNavigationIsClampedAndResetsTheSelection() throws {
        let first = try #require(overview(today: day(10, 10), weekOffset: -1).week)
        #expect(first.index == 1)
        #expect(!first.canGoBack)

        let last = overview(today: day(10, 28), weekOffset: 9)
        #expect(last.week?.index == 8)
        #expect(last.week?.canGoForward == false)

        // The kept selection is outside week 4, so the default rule picks Monday's session.
        let next = overview(today: day(10, 28), weekOffset: 1, selected: day(10, 28))
        #expect(next.week?.index == 4)
        #expect(next.selectedDate == day(11, 2))
    }

    // MARK: Other days

    @Test func beforeTheStart() throws {
        let home = overview(today: day(10, 10))
        let week = try #require(home.week)
        #expect(week.index == 1)
        #expect(!week.days.contains { $0.isToday })
        #expect(home.planCard.pill?.text == "Starts Mon 12 Oct")
        #expect(home.planCard.pill?.isMuted == true)
        #expect(home.planCard.ringValue == "-")
        #expect(home.planCard.ringCaption == "Starts Mon 12 Oct")
        #expect(home.planCard.ringAccessibilityLabel == "Plan has not started")
        #expect(home.planCard.adherence == nil)
        // 21 days left in October, 30 in November, 6 in December.
        #expect(home.planCard.countdownValue == "57")
        #expect(home.selectedDate == day(10, 12))
    }

    @Test func raceDay() {
        let home = overview(today: day(12, 6))
        #expect(home.planCard.countdownValue == "Race day")
        #expect(home.planCard.countdownUnit == nil)
        #expect(home.planCard.weekCaption == "Week 8 of 8")
        #expect(home.selectedCard == .race("10K race"))
        #expect(home.upNext == nil)
    }

    @Test func afterTheRace() {
        let home = overview(today: day(12, 7))
        #expect(home.planCard.countdownValue == "Finished")
        #expect(home.planCard.pill == nil)
        #expect(home.week == nil)
        #expect(home.selectedCard == nil)
    }
}
