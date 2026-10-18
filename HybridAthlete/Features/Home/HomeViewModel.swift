import Foundation
import Observation
import Domain
import Application

/// Home: the plan card, week strip, selected day, up next and the Recovery
/// section (sleep, HRV, resting heart rate). The plan and the completed runs come
/// from the shared stores (so Home and Calendar always agree); recovery is read
/// here. Runs and recovery refresh in parallel; each recovery metric arrives on
/// its own and keeps its own state, so one failing never blocks the others.
/// Every value comes from `GetHomeOverview`.
@MainActor
@Observable
final class HomeViewModel {
    private(set) var isRefreshingRecovery = false
    private(set) var weekOffset = 0

    private var chosenDate: LocalDate?
    private var recovery = RecoveryStates()
    private var hasLoaded = false
    private var lastRecoveryRefreshStart: Date?
    #if DEBUG
    private var lastSleepRead: SleepRead?
    private var lastHRVRead: HRVRead?
    private var lastRestingHRRead: RestingHRRead?
    /// Set by the composition root: whether HealthKit exposes an RMSSD type.
    var sdkHasRmssdType = false
    /// Set by the composition root: builds the DEBUG Model Lab.
    var makeModelLab: (@MainActor () -> ModelLabViewModel)?
    #endif

    private let plans: ActivePlanStore
    private let runs: CompletedRunsStore
    private let loadCachedSleep: LoadCachedSleep
    private let loadCachedRecovery: LoadCachedRecovery
    private let refreshRecoverySection: RefreshRecoverySection
    private let getHomeOverview: GetHomeOverview
    private let deleteActivePlan: DeleteActivePlan
    private let clock: any Clock
    private let onNoPlan: @MainActor () -> Void
    /// The shared coach notes, for the "Latest coach note" card.
    private let notes: CoachNoteStore?
    /// The shared feedback store, for the "Suggested change" card; nil in tests that do not need it.
    var feedback: FeedbackStore?

    init(
        plans: ActivePlanStore,
        runs: CompletedRunsStore,
        loadCachedSleep: LoadCachedSleep,
        loadCachedRecovery: LoadCachedRecovery,
        refreshRecoverySection: RefreshRecoverySection,
        getHomeOverview: GetHomeOverview,
        deleteActivePlan: DeleteActivePlan,
        clock: any Clock,
        notes: CoachNoteStore? = nil,
        onNoPlan: @escaping @MainActor () -> Void
    ) {
        self.notes = notes
        self.plans = plans
        self.runs = runs
        self.loadCachedSleep = loadCachedSleep
        self.loadCachedRecovery = loadCachedRecovery
        self.refreshRecoverySection = refreshRecoverySection
        self.getHomeOverview = getHomeOverview
        self.deleteActivePlan = deleteActivePlan
        self.clock = clock
        self.onNoPlan = onNoPlan
    }

    /// Rebuilt from the shared plan and runs whenever they change.
    var overview: HomeOverview? {
        guard let plan = plans.plan else { return nil }
        return getHomeOverview.execute(plan: plan, runs: runs.result, recovery: recovery, weekOffset: weekOffset, selectedDate: chosenDate)
    }

    var selectedDate: LocalDate? { overview?.selectedDate }

    /// The newest completed session's note; nil when no session has one.
    var latestNote: LatestCoachNoteCard? { notes?.latestCard }

    /// Shows the cached runs and recovery at once, then reads Health. A missing
    /// plan (for example an unreadable file) goes back to the starting point.
    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await plans.loadIfNeeded()
        guard plans.plan != nil else {
            hasLoaded = false
            onNoPlan()
            return
        }
        await runs.loadCached()
        await notes?.load()
        recovery.sleep = await loadCachedSleep.execute()
        (recovery.hrv, recovery.restingHr) = await loadCachedRecovery.execute()
        async let runsDone: Void = runs.refreshIfStale()
        async let recoveryDone: Void = refreshRecovery()
        _ = await (runsDone, recoveryDone)
    }

    /// Pull to refresh: runs and recovery in parallel. The selection is kept.
    func refresh() async {
        guard plans.plan != nil else { return }
        async let runsDone: Void = runs.refresh()
        async let recoveryDone: Void = refreshRecovery()
        _ = await (runsDone, recoveryDone)
    }

    /// "Try again" on any Recovery card. HRV depends on sleep, so the whole
    /// section is read again.
    func retryRecovery() async {
        await refreshRecovery()
    }

    /// Shows each metric as soon as it arrives.
    private func refreshRecovery() async {
        guard !isRefreshingRecovery else { return }
        isRefreshingRecovery = true
        lastRecoveryRefreshStart = clock.now()
        for await update in refreshRecoverySection.execute() {
            switch update {
            case .sleep(let result):
                recovery.sleep = result.state
                #if DEBUG
                lastSleepRead = result.read ?? lastSleepRead
                #endif
            case .hrv(let result):
                recovery.hrv = result.state
                #if DEBUG
                lastHRVRead = result.read ?? lastHRVRead
                #endif
            case .restingHr(let result):
                recovery.restingHr = result.state
                #if DEBUG
                lastRestingHRRead = result.read ?? lastRestingHRRead
                #endif
            }
        }
        isRefreshingRecovery = false
    }

    /// Back in the foreground: each part refreshes when its last refresh is old enough.
    func refreshIfStale() async {
        guard plans.plan != nil else { return }
        async let runsDone: Void = runs.refreshIfStale()
        async let recoveryDone: Void = runs.isStale(since: lastRecoveryRefreshStart) ? refreshRecovery() : ()
        _ = await (runsDone, recoveryDone)
    }

    func select(_ date: LocalDate) {
        chosenDate = date
    }

    /// Changing the week resets the selection by the default rule.
    func showPreviousWeek() {
        guard overview?.week?.canGoBack == true else { return }
        weekOffset -= 1
        chosenDate = nil
    }

    func showNextWeek() {
        guard overview?.week?.canGoForward == true else { return }
        weekOffset += 1
        chosenDate = nil
    }

    #if DEBUG
    /// DEBUG only: the stored plan (with originalDate and isMissed per session)
    /// and an `edits` array of the recent edit log, as JSON.
    var planJSON: String? {
        guard let plan = plans.plan else { return nil }
        return PlanDebugJSON.string(plan: plan, edits: plans.recentEdits)
    }

    /// DEBUG only: which generator built the plan ("template-v1", "on-device-v1"...).
    var generatedBy: String? { plans.plan?.generatedBy }

    /// DEBUG only: the last sleep read (window, sources, nights, the shown
    /// night's segments, what was ignored) as JSON.
    var sleepJSON: String? {
        lastSleepRead.map(SleepDebugJSON.string(read:))
    }

    /// DEBUG only: the last HRV and resting heart rate reads (window, sources,
    /// summaries, the shown night's and day's samples, ignored counts) as JSON.
    var recoveryJSON: String? {
        guard lastHRVRead != nil || lastRestingHRRead != nil else { return nil }
        return RecoveryDebugJSON.string(hrv: lastHRVRead, restingHr: lastRestingHRRead, sdkHasRmssdType: sdkHasRmssdType)
    }

    /// DEBUG "Copy coach note facts": the exact prompt the selected session's
    /// note would send; nil when the session has no completed run.
    func coachNoteFacts() async -> String? {
        guard let date = selectedDate, let id = plans.plan?.session(on: date)?.id else { return nil }
        return await notes?.factsText(for: id)
    }

    /// DEBUG only: delete the plan and go back to the starting point.
    func reset() async {
        try? await deleteActivePlan.execute()
        onNoPlan()
    }
    #endif
}
