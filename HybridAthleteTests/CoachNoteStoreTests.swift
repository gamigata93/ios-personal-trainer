import Foundation
import Testing
import Domain
import Application
import Infrastructure
@testable import HybridAthlete

/// The shared coach notes: auto-generation, the serial queue, manual writes and
/// the Session detail and Home states. Fakes only.
@MainActor
struct CoachNoteStoreTests {
    /// Wed 28 Oct 2026, 09:00 UTC.
    private struct Wednesday: Clock {
        func now() -> Date { Date(timeIntervalSince1970: 1_793_178_000) }
    }

    nonisolated static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private static func day(_ day: Int) -> LocalDate { LocalDate(year: 2026, month: 10, day: day) }
    private static let today = day(28)

    /// A 5.0 km tempo every day from Mon 12 Oct to Sun 1 Nov (weeks from Monday).
    private static let plan: TrainingPlan = {
        let weeks = (0..<3).map { index -> PlanWeek in
            let monday = day(12).adding(days: index * 7)
            let sessions = (0..<7).map { offset in
                PlannedSession(
                    date: monday.adding(days: offset), type: .tempo, name: "Tempo run", distanceKm: 5, estimatedMinutes: 30,
                    effort: "Comfortably hard",
                    segments: [
                        Segment(label: "Warm-up", detail: "Easy jog", distanceKm: 1),
                        Segment(label: "Tempo", detail: "3 km continuous, comfortably hard", distanceKm: 3),
                        Segment(label: "Cool-down", detail: "Easy jog", distanceKm: 1),
                    ],
                    note: nil
                )
            }
            return PlanWeek(index: index + 1, startDate: monday, phase: .base, targetKm: 35, sessions: sessions)
        }
        return TrainingPlan(
            id: "daily", createdAt: .distantPast, generatedBy: "test", planKind: .tenK,
            race: RaceSetup(distanceKm: 10, elevationGainM: 0, raceDate: day(12).adding(days: 55), trainingDays: Set(Weekday.allCases)),
            planStart: day(12), weeks: weeks
        )
    }()

    @MainActor
    private struct Setup {
        let store: CoachNoteStore
        let plans: ActivePlanStore
        let runs: CompletedRunsStore
        let notes: MemoryCoachNotes
        let coaching: any CoachingModel

        func detail(_ sessionId: String) -> SessionDetailViewModel {
            SessionDetailViewModel(
                sessionID: sessionId, plans: plans, runs: runs, notes: store,
                getSessionDetail: GetSessionDetail(clock: Wednesday(), calendar: CoachNoteStoreTests.utc),
                clock: Wednesday(), calendar: CoachNoteStoreTests.utc
            )
        }
    }

    /// Runs of 5.0 km on `runDays` of October.
    private func setup(runDays: [Int], coaching: any CoachingModel = CountingCoachingModel(), notes: MemoryCoachNotes = MemoryCoachNotes()) async -> Setup {
        let runs = runDays.map { CompletedRun(id: "run-\($0)", localDate: Self.day($0), distanceKm: 5, durationSeconds: 1_716, avgHr: 152, maxHr: 170) }
        let cache = StubRunsCache(CachedRuns(generatedAt: Wednesday().now(), planId: Self.plan.id, runs: runs))
        let plans = ActivePlanStore(plans: StubPlans(plan: Self.plan), clock: Wednesday(), calendar: Self.utc)
        await plans.loadIfNeeded()
        let runStore = CompletedRunsStore(
            plans: plans,
            loadCompletedRuns: LoadCompletedRuns(cache: cache),
            refreshCompletedRuns: RefreshCompletedRuns(health: StubHealthDataSource(), cache: cache, clock: Wednesday(), calendar: Self.utc),
            clock: Wednesday()
        )
        await runStore.loadCached()
        let store = makeCoachNotes(
            plans: plans, runs: runStore, clock: Wednesday(), calendar: Self.utc,
            detail: FakeWorkoutDetailSource(scenario: .tempo, runs: { [] }, activePlan: { nil }),
            coaching: coaching, notes: notes, today: Self.today
        )
        return Setup(store: store, plans: plans, runs: runStore, notes: notes, coaching: coaching)
    }

    // MARK: Auto-generation

    @Test func autoGeneratePicksTheThreeNewestRecentSessions() async {
        // Five candidates in the last 7 days (22, 23, 25, 26, 27) and an older one (12).
        let setup = await setup(runDays: [12, 22, 23, 25, 26, 27])
        #expect(setup.store.autoCandidates() == ["2026-10-27", "2026-10-26", "2026-10-25"])
        await setup.store.afterRefresh()
        await setup.store.waitUntilIdle()
        #expect(Set(await setup.notes.stored.keys) == ["2026-10-27", "2026-10-26", "2026-10-25"])
        // The next refresh takes the next ones; the older session is never automatic.
        #expect(setup.store.autoCandidates() == ["2026-10-23", "2026-10-22"])
        await setup.store.afterRefresh()
        await setup.store.waitUntilIdle()
        #expect(await setup.notes.stored["2026-10-12"] == nil)
        #expect(await setup.notes.stored.count == 5)
    }

    @Test func oneGenerationAtATimeAndNeverTwiceForASession() async throws {
        let coaching = CountingCoachingModel()
        let setup = await setup(runDays: [25, 26, 27], coaching: coaching)
        await setup.store.afterRefresh()
        setup.store.write("2026-10-27")
        setup.store.write("2026-10-27")
        await setup.store.open("2026-10-26")
        await setup.store.waitUntilIdle()
        #expect(await coaching.maxRunning == 1)
        #expect(await coaching.calls == 3)
        #expect(await setup.notes.saveCount == 3)
    }

    @Test func manualWriteAndRegenerateForAnOlderSession() async throws {
        let coaching = CountingCoachingModel()
        let setup = await setup(runDays: [12], coaching: coaching)
        let detail = setup.detail("2026-10-12")
        await detail.appear()
        // Older than 7 days: nothing is written until asked.
        #expect(detail.coachCard == .write)
        #expect(await coaching.calls == 0)
        detail.write()
        #expect(detail.coachCard == .generating)
        await setup.store.waitUntilIdle()
        guard case .ready(let first) = detail.coachCard else { Issue.record("no note"); return }
        #expect(first.note.headline == "Steady" && !first.isStale)
        #expect(first.footer.hasPrefix("Written by Apple Private Cloud · "))
        detail.regenerate()
        await setup.store.waitUntilIdle()
        #expect(await coaching.calls == 2)
        #expect(await setup.notes.saveCount == 2)
    }

    // MARK: Session detail

    @Test func aRecentSessionIsWrittenOnOpen() async {
        let setup = await setup(runDays: [26])
        let detail = setup.detail("2026-10-26")
        await detail.appear()
        #expect(detail.coachCard == .generating)
        // The breakdown is there before the note.
        let breakdown = detail.breakdown
        #expect(breakdown?.tiles.map(\.id) == ["distance", "moving", "pace", "hr", "elevation"])
        #expect(breakdown?.blocks.map(\.chip) == ["On target", "On target", "On target"])
        #expect(breakdown?.zones.map(\.minutesText) == ["0 min", "13 min", "0 min", "15 min", "0 min"])
        #expect(breakdown?.zones.filter(\.isTarget).map(\.zone) == [3, 4])
        #expect(breakdown?.verdict == .onTrack)
        #expect(breakdown?.footnote == "Based on heart rate and route from Apple Watch.")
        await setup.store.waitUntilIdle()
        guard case .ready(let ready) = detail.coachCard else { Issue.record("no note"); return }
        #expect(ready.spoken.hasPrefix("Coach's note. Steady. How it went: A controlled run."))
    }

    @Test func aNoteForAnotherRunIsStale() async throws {
        let notes = MemoryCoachNotes()
        let old = SavedCoachNote(
            planId: Self.plan.id, sessionId: "2026-10-26", runId: "an-older-run", createdAt: Wednesday().now(), source: .model,
            provider: .apple, modelTag: "onDevice", note: CoachNote(headline: "Old", howItWent: "A.", versusPlan: "B.", programStatus: "C.", nextStep: "D."),
            verdict: .onTrack, inputHash: "x", factsLevel: 0
        )
        try await notes.save(old)
        let setup = await setup(runDays: [26], notes: notes)
        let detail = setup.detail("2026-10-26")
        await detail.appear()
        guard case .ready(let ready) = detail.coachCard else { Issue.record("no note"); return }
        #expect(ready.isStale && ready.note.headline == "Old")
    }

    @Test func anUnexpectedFailureOffersTryAgain() async {
        let setup = await setup(runDays: [26], coaching: FakeCoachNoteModel(scenario: .fail))
        let detail = setup.detail("2026-10-26")
        await detail.appear()
        await setup.store.waitUntilIdle()
        #expect(detail.coachCard == .failed)
        detail.write()
        await setup.store.waitUntilIdle()
        guard case .ready(let ready) = detail.coachCard else { Issue.record("no note"); return }
        // The canned note matches this run's facts except the program line: rejected twice, so the rules wrote it.
        #expect(ready.footer.hasPrefix("Written by "))
    }

    @Test func notCompletedSessionsHaveNoCard() async {
        let setup = await setup(runDays: [])
        let detail = setup.detail("2026-10-26")
        await detail.appear()
        #expect(detail.coachCard == .hidden && detail.breakdown == nil)
        #expect(setup.detail("2026-10-30").coachCard == .hidden)
    }

    // MARK: Home

    @Test func homeShowsTheNewestNote() async {
        let setup = await setup(runDays: [23, 26])
        #expect(setup.store.latestCard == nil)
        await setup.store.afterRefresh()
        await setup.store.waitUntilIdle()
        let card = setup.store.latestCard
        #expect(card?.sessionId == "2026-10-26")
        #expect(card?.headline == "Steady" && card?.summary == "A controlled run.")
        #expect(card?.footer == "Tempo run · Mon 26 Oct")
    }
}
