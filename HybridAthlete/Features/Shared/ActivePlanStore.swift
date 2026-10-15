import Foundation
import Observation
import Domain
import Application

/// The notice after a plan edit: its text, the optional heads-up, and what Undo needs.
struct PlanEditNotice: Equatable {
    let editId: Int64
    /// "Moved Easy run to Thu 29 Oct."
    let text: String
    /// "Heads-up: two hard sessions on back-to-back days."
    let headsUp: String?
    /// The day to select after Undo.
    let undoFocusDate: LocalDate
}

/// The single shared state for the active plan, read by Home, Calendar and
/// Session detail. It holds state and calls use cases; the rules live in Domain.
@MainActor
@Observable
final class ActivePlanStore {
    private(set) var plan: TrainingPlan?
    private(set) var hasLoaded = false
    /// The latest edit's notice, until Undo, another edit, or the screen clears it.
    private(set) var notice: PlanEditNotice?
    /// Set when an edit or an undo failed; the plan is unchanged.
    private(set) var editFailed = false
    #if DEBUG
    /// The newest edit-log entries, for "Copy plan JSON".
    private(set) var recentEdits: [PlanEditRecord] = []
    #endif

    private let loadActivePlan: LoadActivePlan
    private let applyPlanEdit: ApplyPlanEdit
    private let undoPlanEdit: UndoPlanEdit
    private let loadRecentPlanEdits: LoadRecentPlanEdits
    private var inFlight: Task<Void, Never>?

    init(
        loadActivePlan: LoadActivePlan,
        applyPlanEdit: ApplyPlanEdit,
        undoPlanEdit: UndoPlanEdit,
        loadRecentPlanEdits: LoadRecentPlanEdits
    ) {
        self.loadActivePlan = loadActivePlan
        self.applyPlanEdit = applyPlanEdit
        self.undoPlanEdit = undoPlanEdit
        self.loadRecentPlanEdits = loadRecentPlanEdits
    }

    /// Reads the stored plan again.
    func reload() async {
        if let inFlight { return await inFlight.value }
        let task = Task {
            plan = await loadActivePlan.execute()
            #if DEBUG
            if let id = plan?.id {
                recentEdits = await loadRecentPlanEdits.execute(planId: id)
            }
            #endif
        }
        inFlight = task
        await task.value
        hasLoaded = true
        inFlight = nil
    }

    /// The first read; later calls reuse it.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    /// Saves an edit and reloads the plan. On success the notice replaces any
    /// earlier one; on failure the plan is reloaded unchanged and `editFailed` is set.
    /// Returns the outcome, or nil when nothing changed.
    @discardableResult
    func apply(_ edit: PlanEdit, runs: [CompletedRun]) async -> PlanEditOutcome? {
        notice = nil
        editFailed = false
        do {
            let outcome = try await applyPlanEdit.execute(edit, runs: runs)
            notice = PlanEditNotice(
                editId: outcome.receipt.editId,
                text: outcome.notice,
                headsUp: outcome.headsUp,
                undoFocusDate: outcome.undoFocusDate
            )
            await reload()
            return outcome
        } catch {
            editFailed = true
            await reload()
            return nil
        }
    }

    /// Reverts the edit behind the current notice. Returns the day to select again,
    /// or nil when there was nothing to undo or it failed.
    @discardableResult
    func undo() async -> LocalDate? {
        guard let notice else { return nil }
        self.notice = nil
        do {
            try await undoPlanEdit.execute(editId: notice.editId)
            await reload()
            return notice.undoFocusDate
        } catch {
            editFailed = true
            await reload()
            return nil
        }
    }

    /// Leaving the screen, selecting another day, or Dismiss.
    func clearNotice() {
        notice = nil
        editFailed = false
    }
}
