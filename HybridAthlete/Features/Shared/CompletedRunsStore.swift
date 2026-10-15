import Foundation
import Observation
import Domain
import Application

/// The single shared state for completed runs, read by Home, Calendar and
/// Session detail, so they always agree. One refresh serves every screen and
/// never runs twice at once. It holds state and calls use cases; nothing else.
@MainActor
@Observable
final class CompletedRunsStore {
    enum RefreshState: Equatable {
        case idle
        case refreshing
        /// Health was locked; the runs are cached ones from `asOf`.
        case locked(asOf: Date?)
    }

    private(set) var result: CompletedRunsResult = .none
    private(set) var state: RefreshState = .idle

    private let plans: ActivePlanStore
    private let loadCompletedRuns: LoadCompletedRuns
    private let refreshCompletedRuns: RefreshCompletedRuns
    private let clock: any Clock
    private var lastRefreshStart: Date?
    private var cachedPlanID: String?
    private var inFlight: Task<Void, Never>?

    init(
        plans: ActivePlanStore,
        loadCompletedRuns: LoadCompletedRuns,
        refreshCompletedRuns: RefreshCompletedRuns,
        clock: any Clock
    ) {
        self.plans = plans
        self.loadCompletedRuns = loadCompletedRuns
        self.refreshCompletedRuns = refreshCompletedRuns
        self.clock = clock
    }

    /// Shows the cached runs for the current plan before Health is read.
    func loadCached() async {
        guard let plan = plans.plan, cachedPlanID != plan.id else { return }
        cachedPlanID = plan.id
        if result == .none {
            result = await loadCompletedRuns.execute(for: plan)
        }
    }

    /// Pull to refresh. A call while a refresh runs waits for that one.
    func refresh() async {
        if let inFlight { return await inFlight.value }
        guard let plan = plans.plan else { return }
        lastRefreshStart = clock.now()
        state = .refreshing
        let task = Task {
            let fresh = await refreshCompletedRuns.execute(for: plan)
            result = fresh
            state = fresh.isLocked ? .locked(asOf: fresh.asOf) : .idle
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    /// Opening a tab and returning to the foreground: refresh when the last one
    /// is at least the staleness interval (5 minutes) old.
    func refreshIfStale() async {
        guard isStale(since: lastRefreshStart) else {
            if let inFlight { await inFlight.value }
            return
        }
        await refresh()
    }

    /// Whether something started at `date` is old enough to repeat (the same rule as runs).
    func isStale(since date: Date?) -> Bool {
        refreshCompletedRuns.isStale(lastRefreshStart: date)
    }
}
