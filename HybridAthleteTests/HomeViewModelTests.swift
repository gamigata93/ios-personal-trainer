import Foundation
import Testing
import Domain
import Application
import Infrastructure
@testable import HybridAthlete

@MainActor
struct HomeViewModelTests {
    /// Wed 28 Oct 2026, 09:00 UTC.
    private struct Wednesday: Clock {
        func now() -> Date { Date(timeIntervalSince1970: 1_793_178_000) }
    }

    /// Runs from `-fakeRuns` for the seed plan, sleep from `-fakeSleep normal` and
    /// HRV and resting heart rate from `-fakeRecovery mock`, each of which can be
    /// made to fail on its own.
    private actor FakeHealth: HealthDataSource {
        var runsError: HealthDataError?
        var sleepError: HealthDataError?
        var hrvError: HealthDataError?
        var restingError: HealthDataError?

        init(
            runsError: HealthDataError? = nil,
            sleepError: HealthDataError? = nil,
            hrvError: HealthDataError? = nil,
            restingError: HealthDataError? = nil
        ) {
            self.runsError = runsError
            self.sleepError = sleepError
            self.hrvError = hrvError
            self.restingError = restingError
        }

        func set(runsError: HealthDataError?) { self.runsError = runsError }
        func set(sleepError: HealthDataError?) { self.sleepError = sleepError }
        func set(hrvError: HealthDataError?) { self.hrvError = hrvError }

        private var recovery: FakeRecoveryHealthDataSource {
            FakeRecoveryHealthDataSource(base: self, scenario: .mock, clock: Wednesday(), calendar: HomeViewModelTests.utc)
        }

        func hrvSamples(from: Date, to: Date) async throws -> [HRVSample] {
            if let hrvError { throw hrvError }
            return try await recovery.hrvSamples(from: from, to: to)
        }

        func restingHeartRateSamples(from: Date, to: Date) async throws -> [RestingHRSample] {
            if let restingError { throw restingError }
            return try await recovery.restingHeartRateSamples(from: from, to: to)
        }

        func authorizationRequestStatus() async -> HealthAuthorizationRequestStatus { .alreadyRequested }
        func requestAccess() async throws {}
        func readProfile() async throws -> HealthProfile { HealthProfile(ageYears: nil, biologicalSex: nil) }
        func readSamples(_ kind: HealthMetricKind, since: Date?, limit: Int?) async throws -> [HealthSample] { [] }
        func readWorkouts(routeCheckLimit: Int) async throws -> [WorkoutSummary] { [] }

        func runningWorkouts(from: LocalDate, to: LocalDate) async throws -> [RunSummary] {
            if let runsError { throw runsError }
            return try await FakeRunsHealthDataSource(
                base: self, activePlan: { SeedPlan.plan(createdAt: .distantPast) }, clock: Wednesday(), calendar: HomeViewModelTests.utc
            ).runningWorkouts(from: from, to: to)
        }

        func sleepSegments(from: Date, to: Date) async throws -> [SleepSegment] {
            if let sleepError { throw sleepError }
            return try await FakeSleepHealthDataSource(base: self, scenario: .normal, clock: Wednesday(), calendar: HomeViewModelTests.utc)
                .sleepSegments(from: from, to: to)
        }
    }

    nonisolated static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// Home, Calendar and Session detail around one shared plan store and runs store.
    private func makeScreens(
        health: FakeHealth,
        plans: StubPlans = StubPlans(plan: SeedPlan.plan(createdAt: .distantPast)),
        onNoPlan: @escaping @MainActor () -> Void = {}
    ) -> MainScreens {
        let runsCache = StubRunsCache()
        let sleep = StubSleepCache()
        let recovery = StubRecoveryCache()
        let planStore = ActivePlanStore(plans: plans, clock: Wednesday(), calendar: Self.utc)
        let runs = CompletedRunsStore(
            plans: planStore,
            loadCompletedRuns: LoadCompletedRuns(cache: runsCache),
            refreshCompletedRuns: RefreshCompletedRuns(health: health, cache: runsCache, clock: Wednesday(), calendar: Self.utc),
            clock: Wednesday()
        )
        let home = HomeViewModel(
            plans: planStore,
            runs: runs,
            loadCachedSleep: LoadCachedSleep(cache: sleep),
            loadCachedRecovery: LoadCachedRecovery(cache: recovery),
            refreshRecoverySection: RefreshRecoverySection(
                refreshSleep: RefreshSleep(health: health, cache: sleep, clock: Wednesday(), calendar: Self.utc),
                loadCachedSleep: LoadCachedSleep(cache: sleep),
                refreshRecovery: RefreshRecovery(health: health, cache: recovery, clock: Wednesday(), calendar: Self.utc)
            ),
            getHomeOverview: GetHomeOverview(
                clock: Wednesday(), calendar: Self.utc,
                sleepOverview: GetSleepOverview(calendar: Self.utc, locale: Locale(identifier: "en_GB")),
                recoveryOverview: GetRecoveryOverview()
            ),
            deleteActivePlan: DeleteActivePlan(plans: plans),
            clock: Wednesday(),
            onNoPlan: onNoPlan
        )
        let getSessionDetail = GetSessionDetail(clock: Wednesday(), calendar: Self.utc)
        return MainScreens(
            plans: planStore,
            runs: runs,
            home: home,
            calendar: CalendarViewModel(plans: planStore, runs: runs, getCalendarMonth: GetCalendarMonth(clock: Wednesday(), calendar: Self.utc)),
            makeSessionDetail: { SessionDetailViewModel(sessionID: $0, plans: planStore, runs: runs, getSessionDetail: getSessionDetail) }
        )
    }

    private func makeHome(
        health: FakeHealth,
        plans: StubPlans = StubPlans(plan: SeedPlan.plan(createdAt: .distantPast)),
        onNoPlan: @escaping @MainActor () -> Void = {}
    ) -> HomeViewModel {
        makeScreens(health: health, plans: plans, onNoPlan: onNoPlan).home
    }

    private func day(_ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: 2026, month: month, day: day)
    }

    private func sleepDuration(_ home: HomeViewModel) -> String? {
        guard case .overview(let overview) = home.overview?.recovery.sleep.body else { return nil }
        return overview.durationText
    }

    private func value(_ card: RecoveryMetricCard?) -> String? {
        guard case .overview(let overview) = card?.body else { return nil }
        return overview.valueText
    }

    @Test func theRingShowsTheAdherence() async {
        let home = makeHome(health: FakeHealth())
        await home.load()
        #expect(home.overview?.planCard.ringValue == "86%")
        #expect(home.overview?.planCard.ringAccessibilityLabel == "Plan adherence 86 percent")
        #expect(home.selectedDate == day(10, 28))
    }

    @Test func theSelectionSurvivesARefresh() async {
        let home = makeHome(health: FakeHealth())
        await home.load()
        home.select(day(10, 30))
        await home.refresh()
        #expect(home.selectedDate == day(10, 30))
        guard case .session(let card) = home.overview?.selectedCard else {
            Issue.record("Expected a session card")
            return
        }
        #expect(card.name == "Long run")
    }

    @Test func aRecoveryRefreshDoesNotChangeTheSelection() async {
        let home = makeHome(health: FakeHealth())
        await home.load()
        home.select(day(10, 30))
        await home.retryRecovery()
        #expect(home.selectedDate == day(10, 30))
        #expect(home.overview?.week?.index == 3)
    }

    @Test func changingTheWeekResetsTheSelection() async {
        let home = makeHome(health: FakeHealth())
        await home.load()
        home.select(day(10, 30))
        home.showNextWeek()
        #expect(home.overview?.week?.index == 4)
        #expect(home.selectedDate == day(11, 2))
        home.showPreviousWeek()
        #expect(home.selectedDate == day(10, 28))
    }

    @Test func runsAndSleepRefreshIndependently() async {
        let sleepFails = makeHome(health: FakeHealth(sleepError: .failed))
        await sleepFails.load()
        #expect(sleepFails.overview?.planCard.ringValue == "86%")
        #expect(sleepFails.overview?.recovery.sleep.body == .failed)

        let runsFail = makeHome(health: FakeHealth(runsError: .failed))
        await runsFail.load()
        #expect(runsFail.overview?.planCard.ringValue == "0%")
        #expect(sleepDuration(runsFail) == "7h 30m")
    }

    @Test func theRunsLockedLineAppearsOnlyWhenLocked() async {
        let health = FakeHealth()
        let home = makeHome(health: health)
        await home.load()
        #expect(home.overview?.lockedLine == nil)

        await health.set(runsError: .locked)
        await home.refresh()
        #expect(home.overview?.lockedLine == "Your phone is locked. Showing progress from just now.")
        #expect(home.overview?.planCard.ringValue == "86%")
        #expect(home.overview?.recovery.lockedNotice == nil)
    }

    @Test func theRecoveryLockedLineAppearsWhenAnyMetricIsLocked() async {
        let health = FakeHealth()
        let home = makeHome(health: health)
        await home.load()
        #expect(home.overview?.recovery.lockedNotice == nil)
        #expect(sleepDuration(home) == "7h 30m")

        await health.set(sleepError: .locked)
        await home.refresh()
        #expect(home.overview?.recovery.lockedNotice == "Your phone is locked. Showing recovery from just now.")
        #expect(sleepDuration(home) == "7h 30m")
        #expect(home.overview?.lockedLine == nil)

        await health.set(sleepError: nil)
        await health.set(hrvError: .locked)
        await home.refresh()
        #expect(home.overview?.recovery.lockedNotice == "Your phone is locked. Showing recovery from just now.")
        #expect(value(home.overview?.recovery.hrv) == "58")
    }

    @Test func theThreeRecoveryMetricsAreIndependent() async {
        let all = makeHome(health: FakeHealth())
        await all.load()
        #expect(sleepDuration(all) == "7h 30m")
        #expect(value(all.overview?.recovery.hrv) == "58")
        #expect(value(all.overview?.recovery.restingHr) == "49")

        let hrvFails = makeHome(health: FakeHealth(hrvError: .failed))
        await hrvFails.load()
        #expect(hrvFails.overview?.recovery.hrv.body == .failed)
        #expect(sleepDuration(hrvFails) == "7h 30m")
        #expect(value(hrvFails.overview?.recovery.restingHr) == "49")

        let restingFails = makeHome(health: FakeHealth(restingError: .failed))
        await restingFails.load()
        #expect(restingFails.overview?.recovery.restingHr.body == .failed)
        #expect(value(restingFails.overview?.recovery.hrv) == "58")

        // Sleep failing: HRV falls back to the overnight window and still shows.
        let sleepFails = makeHome(health: FakeHealth(sleepError: .failed))
        await sleepFails.load()
        #expect(sleepFails.overview?.recovery.sleep.body == .failed)
        #expect(value(sleepFails.overview?.recovery.hrv) == "58")
        #expect(value(sleepFails.overview?.recovery.restingHr) == "49")
    }

    @Test func aMissingPlanGoesBack() async {
        var wentBack = false
        let home = makeHome(health: FakeHealth(), plans: StubPlans(), onNoPlan: { wentBack = true })
        await home.load()
        #expect(wentBack)
        #expect(home.overview == nil)
    }

    @Test func sessionDetailWordsTheSession() async throws {
        let screens = makeScreens(health: FakeHealth())
        await screens.home.load()
        let detail = try #require(screens.makeSessionDetail("2026-10-30").detail)
        #expect(detail.name == "Long run")
        #expect(detail.distance == "9.0 km")
        #expect(detail.estimatedTime == "~50 min")
        #expect(detail.weekPhaseLine == "Week 3 of 8 · Base phase")
        #expect(!detail.segments.isEmpty)
        #expect(screens.makeSessionDetail("2026-10-29").detail == nil)
    }

    // MARK: Calendar

    @Test func homeAndCalendarSeeTheSameRuns() async throws {
        let screens = makeScreens(health: FakeHealth())
        await screens.home.load()
        let month = try #require(screens.calendar.overview)
        #expect(month.title == "October 2026")
        #expect(month.selectedDate == day(10, 28))
        let completedInCalendar = month.cells.filter { $0.status == .completed }.count
        let completedOnHome = try #require(screens.home.overview).completedCount
        #expect(completedInCalendar == completedOnHome)
    }

    @Test func monthArrowsResetTheSelection() async {
        let screens = makeScreens(health: FakeHealth())
        let calendar = screens.calendar
        await calendar.appear()
        #expect(calendar.overview?.canGoBack == false)
        calendar.showPreviousMonth()
        #expect(calendar.overview?.title == "October 2026")

        calendar.select(day(10, 30))
        #expect(calendar.selectedDate == day(10, 30))
        calendar.showNextMonth()
        #expect(calendar.overview?.title == "November 2026")
        #expect(calendar.selectedDate == day(11, 2))
        calendar.showPreviousMonth()
        #expect(calendar.selectedDate == day(10, 28))
    }

    @Test func daysOutsideThePlanCannotBeSelected() async {
        let calendar = makeScreens(health: FakeHealth()).calendar
        await calendar.appear()
        calendar.select(day(10, 5))
        #expect(calendar.selectedDate == day(10, 28))
    }

    @Test func theCalendarSelectionSurvivesARefresh() async {
        let calendar = makeScreens(health: FakeHealth()).calendar
        await calendar.appear()
        calendar.select(day(10, 30))
        await calendar.refresh()
        #expect(calendar.selectedDate == day(10, 30))
        guard case .session(let card) = calendar.overview?.dayCard else {
            Issue.record("Expected a session card")
            return
        }
        #expect(card.name == "Long run")
    }

    @Test func theCalendarShowsTheLockedLine() async {
        let health = FakeHealth()
        let screens = makeScreens(health: health)
        await screens.calendar.appear()
        #expect(screens.calendar.overview?.lockedLine == nil)
        await health.set(runsError: .locked)
        await screens.calendar.refresh()
        #expect(screens.calendar.overview?.lockedLine == "Your phone is locked. Showing progress from just now.")
        #expect(screens.runs.state == .locked(asOf: Wednesday().now()))
    }

    // MARK: Plan edits on the Calendar

    private func calendarOn28(_ plans: StubPlans = StubPlans(plan: SeedPlan.plan(createdAt: .distantPast))) async -> MainScreens {
        let screens = makeScreens(health: FakeHealth(), plans: plans)
        await screens.calendar.appear()
        await screens.runs.refresh()
        screens.calendar.select(day(10, 28))
        return screens
    }

    private func action(_ kind: PlanAction.Kind, _ calendar: CalendarViewModel) throws -> PlanAction {
        try #require(calendar.overview?.actions.first { $0.kind == kind })
    }

    @Test func startingAMoveSetsTheTargetsAndCancelClearsThem() async throws {
        let screens = await calendarOn28()
        let calendar = screens.calendar
        await calendar.perform(try action(.moveAnotherDay, calendar))
        #expect(calendar.mode == .moving(sessionId: "2026-10-28"))
        #expect(calendar.targetDates.contains(day(10, 29)))
        #expect(!calendar.targetDates.contains(day(10, 30)))
        #expect(calendar.overview?.banner?.text == "Moving Easy run. Tap a free day, today or later.")
        #expect(calendar.overview?.actions.isEmpty == true)
        calendar.cancelEdit()
        #expect(calendar.mode == nil)
        #expect(calendar.targetDates.isEmpty)
        #expect(calendar.selectedDate == day(10, 28))
        #expect(screens.plans.plan == SeedPlan.plan(createdAt: .distantPast))
    }

    @Test func tappingATargetAppliesTheMoveAndAnInvalidTapIsIgnored() async throws {
        let screens = await calendarOn28()
        let calendar = screens.calendar
        await calendar.perform(try action(.moveAnotherDay, calendar))
        await calendar.tap(day(10, 30))
        #expect(calendar.mode == .moving(sessionId: "2026-10-28"))
        #expect(screens.plans.notice == nil)
        await calendar.tap(day(10, 29))
        #expect(calendar.mode == nil)
        #expect(calendar.selectedDate == day(10, 29))
        #expect(calendar.notice?.text == "Moved Easy run to Thu 29 Oct.")
        #expect(screens.plans.plan?.session(id: "2026-10-28")?.date == day(10, 29))
        guard case .session(let card) = calendar.overview?.dayCard else { Issue.record("no card"); return }
        #expect(card.movedFrom == "Moved from Wed 28 Oct")
    }

    @Test func monthArrowsKeepTheModeAndUndoSwitchesBack() async throws {
        let screens = await calendarOn28()
        let calendar = screens.calendar
        await calendar.perform(try action(.moveAnotherDay, calendar))
        calendar.showNextMonth()
        #expect(calendar.mode == .moving(sessionId: "2026-10-28"))
        #expect(calendar.overview?.title == "November 2026")
        await calendar.tap(day(11, 3))
        #expect(calendar.selectedDate == day(11, 3))
        #expect(calendar.overview?.title == "November 2026")
        #expect(calendar.notice?.text == "Moved Easy run to Tue 3 Nov.")
        await calendar.undo()
        #expect(calendar.notice == nil)
        #expect(calendar.selectedDate == day(10, 28))
        #expect(calendar.overview?.title == "October 2026")
        #expect(screens.plans.plan == SeedPlan.plan(createdAt: .distantPast))
    }

    @Test func nextDaySwapAndTheNoticeLifecycle() async throws {
        let screens = await calendarOn28()
        let calendar = screens.calendar
        await calendar.perform(try action(.moveNextDay, calendar))
        #expect(calendar.notice?.text == "Moved Easy run to Thu 29 Oct.")
        // A new edit replaces the notice.
        calendar.select(day(10, 30))
        #expect(calendar.notice == nil)
        await calendar.perform(try action(.swap, calendar))
        #expect(calendar.mode == .swapping(sessionId: "2026-10-30"))
        #expect(calendar.targetDates.contains(day(10, 29)))
        await calendar.tap(day(10, 29))
        #expect(calendar.notice?.text == "Swapped: Long run is now on Thu 29 Oct, Easy run on Fri 30 Oct.")
        #expect(calendar.selectedDate == day(10, 29))
        // Leaving the screen clears it.
        calendar.leave()
        #expect(calendar.notice == nil)
    }

    @Test func switchingTabsCancelsTheMode() async throws {
        let screens = await calendarOn28()
        await screens.calendar.perform(try action(.swap, screens.calendar))
        #expect(screens.calendar.mode != nil)
        screens.calendar.leave()
        #expect(screens.calendar.mode == nil)
    }

    @Test func markingMissedShowsOnHomeAndKeepsAdherence() async throws {
        let screens = await calendarOn28()
        let calendar = screens.calendar
        calendar.select(day(10, 21))
        #expect(calendar.overview?.actions.map(\.kind) == [.moveAnotherDay, .markMissed])
        await calendar.perform(try action(.markMissed, calendar))
        #expect(calendar.notice?.text == "Marked Easy run as missed.")
        #expect(calendar.overview?.cells.first { $0.date == day(10, 21) }?.status == .missed)
        await screens.home.load()
        #expect(screens.home.overview?.planCard.ringValue == "86%")
        screens.home.showPreviousWeek()
        #expect(screens.home.overview?.week?.days.first { $0.date == day(10, 21) }?.status == .missed)
    }

    @Test func aFailedEditLeavesThePlanAndShowsTheFailure() async throws {
        let plans = StubPlans(plan: SeedPlan.plan(createdAt: .distantPast))
        let screens = await calendarOn28(plans)
        await plans.setEditFailure(PlanRepositoryError.stalePlan)
        await screens.calendar.perform(try action(.moveNextDay, screens.calendar))
        #expect(screens.plans.editFailed)
        #expect(screens.calendar.failureText == "Couldn't apply that change. Your plan is unchanged.")
        #expect(screens.calendar.notice == nil)
        #expect(screens.plans.plan == SeedPlan.plan(createdAt: .distantPast))
        screens.calendar.dismissFailure()
        #expect(screens.calendar.failureText == nil)
    }

    @Test func aSuccessfulEditReloadsTheStore() async throws {
        let plans = StubPlans(plan: SeedPlan.plan(createdAt: .distantPast))
        let store = ActivePlanStore(plans: plans, clock: Wednesday(), calendar: Self.utc)
        await store.loadIfNeeded()
        let outcome = await store.apply(.markMissed(sessionId: "2026-10-21"), runs: [])
        #expect(outcome != nil)
        #expect(store.plan?.session(id: "2026-10-21")?.isMissed == true)
        #expect(store.notice?.text == "Marked Easy run as missed.")
        #expect(store.recentEdits.count == 1)
        #expect(await store.undo() == day(10, 21))
        #expect(store.plan?.session(id: "2026-10-21")?.isMissed == false)
    }
}
