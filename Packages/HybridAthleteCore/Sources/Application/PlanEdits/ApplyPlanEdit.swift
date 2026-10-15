import Foundation
import Domain

/// Why an edit or an undo did not happen. Nothing is saved in any of these cases.
public enum PlanEditError: Error, Sendable, Equatable {
    case noActivePlan
    case invalid([EditViolation])
    /// The plan changed underneath the edit.
    case stalePlan
    case cannotUndo
    case saveFailed
}

/// What a saved edit shows: the notice, the optional heads-up, and which days
/// to select now and after Undo.
public struct PlanEditOutcome: Sendable, Equatable {
    public let receipt: EditReceipt
    /// "Moved Easy run to Thu 29 Oct."
    public let notice: String
    /// "Heads-up: two hard sessions on back-to-back days." or nil.
    public let headsUp: String?
    /// The day the edited session is on now.
    public let focusDate: LocalDate
    /// The day to select again after Undo.
    public let undoFocusDate: LocalDate
}

/// Validates an edit against the plan edit rules and saves it.
public struct ApplyPlanEdit: Sendable {
    private let plans: any PlanRepository
    private let clock: any Clock
    private let calendar: Calendar

    public init(plans: any PlanRepository, clock: any Clock, calendar: Calendar) {
        self.plans = plans
        self.clock = clock
        self.calendar = calendar
    }

    public func execute(_ edit: PlanEdit, runs: [CompletedRun]) async throws(PlanEditError) -> PlanEditOutcome {
        guard let plan = await plans.loadActive() else { throw .noActivePlan }
        let today = LocalDate(date: clock.now(), calendar: calendar)
        let violations = PlanEditValidator.violations(plan: plan, runs: runs, today: today, edit: edit)
        guard violations.isEmpty else { throw .invalid(violations) }
        guard
            let notice = PlanEditFormat.notice(for: edit, in: plan),
            let change = PlanChange.make(edit, current: PlanEditApplier.placements(of: plan))
        else { throw .stalePlan }

        let receipt: EditReceipt
        do {
            receipt = try await plans.applyEdit(planId: plan.id, edit: edit)
        } catch PlanRepositoryError.stalePlan {
            throw .stalePlan
        } catch PlanRepositoryError.noActivePlan {
            throw .noActivePlan
        } catch {
            throw .saveFailed
        }

        let edited = PlanEditApplier.apply(change, to: plan)
        let warns = HardDaysWarning.applies(plan: edited, editedDates: Set(change.after.map(\.date)))
        let (focus, undoFocus) = Self.focus(edit, change: change)
        return PlanEditOutcome(
            receipt: receipt,
            notice: notice,
            headsUp: warns ? PlanEditFormat.headsUp : nil,
            focusDate: focus,
            undoFocusDate: undoFocus
        )
    }

    /// Move: the target, then the old day. Swap: the tapped session's day, then the
    /// source's. Missed: the session's day both times.
    private static func focus(_ edit: PlanEdit, change: PlanChange) -> (LocalDate, LocalDate) {
        switch edit {
        case .move(_, let from, let to): (to, from)
        case .swap(_, _, let dateA, let dateB): (dateB, dateA)
        case .markMissed: (change.after[0].date, change.before[0].date)
        }
    }
}
