import Foundation

/// A soft check after an edit: two hard sessions on back-to-back days. Never blocks.
public enum HardDaysWarning {
    /// True when two hard-type sessions (`PlanEditRules.hardTypes`) sit on
    /// consecutive dates and one of those dates was edited.
    public static func applies(plan: TrainingPlan, editedDates: Set<LocalDate>) -> Bool {
        let hardDays = Set(plan.sessions.filter { PlanEditRules.hardTypes.contains($0.type) }.map(\.date))
        return editedDates.contains { date in
            hardDays.contains(date) && (hardDays.contains(date.adding(days: -1)) || hardDays.contains(date.adding(days: 1)))
        }
    }
}

/// Plain English text for plan edits. Pure and locale-independent.
public enum PlanEditFormat {
    public static let headsUp = "Heads-up: two hard sessions on back-to-back days."
    public static let failure = "Couldn't apply that change. Your plan is unchanged."

    /// "Moved Easy run to Thu 29 Oct.", "Swapped: Easy run is now on Fri 30 Oct,
    /// Long run on Wed 28 Oct." or "Marked Easy run as missed.", worded from the plan
    /// before the edit. Nil when a session is missing.
    public static func notice(for edit: PlanEdit, in plan: TrainingPlan) -> String? {
        switch edit {
        case .move(let id, _, let to):
            return plan.session(id: id).map { "Moved \($0.name) to \(HomeFormat.shortDate(to))." }
        case .swap(let a, let b, let dateA, let dateB):
            guard let first = plan.session(id: a), let second = plan.session(id: b) else { return nil }
            return "Swapped: \(first.name) is now on \(HomeFormat.shortDate(dateB)), \(second.name) on \(HomeFormat.shortDate(dateA))."
        case .markMissed(let id):
            return plan.session(id: id).map { "Marked \($0.name) as missed." }
        }
    }

    /// "Moved from Mon 26 Oct" for a session that is not on its original day.
    public static func movedFrom(_ session: PlannedSession) -> String? {
        session.isMoved ? "Moved from \(HomeFormat.shortDate(session.originalDate))" : nil
    }
}
