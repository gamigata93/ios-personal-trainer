import Foundation

/// Why an edit is not allowed. Nothing is saved when there is any.
public enum EditViolation: Sendable, Equatable {
    case sessionNotFound
    /// Completed sessions never change.
    case completed
    case sameDate
    case targetOccupied
    case targetBeforeEarliest
    case targetAfterLatest
    /// A swap needs two different sessions that are both today or upcoming.
    case notSwappable
    /// Only not-recorded or today's sessions can be marked missed.
    case cannotMarkMissed
}

/// Checks an edit against the plan edit rules (`PlanEditRules`). Pure.
public enum PlanEditValidator {
    public static func violations(plan: TrainingPlan, runs: [CompletedRun], today: LocalDate, edit: PlanEdit) -> [EditViolation] {
        let progress = PlanProgress(plan: plan, runs: runs, today: today)
        switch edit {
        case .move(let id, _, let to):
            guard let session = plan.session(id: id) else { return [.sessionNotFound] }
            if progress.status(of: session) == .completed { return [.completed] }
            if to == session.date { return [.sameDate] }
            return targetViolations(to, plan: plan, today: today)
        case .swap(let a, let b, _, _):
            guard let first = plan.session(id: a), let second = plan.session(id: b) else { return [.sessionNotFound] }
            let swappable: Set<SessionStatus> = [.today, .upcoming]
            guard a != b, swappable.contains(progress.status(of: first)), swappable.contains(progress.status(of: second)) else {
                return [.notSwappable]
            }
            return []
        case .markMissed(let id):
            guard let session = plan.session(id: id) else { return [.sessionNotFound] }
            switch progress.status(of: session) {
            case .completed: return [.completed]
            case .notRecorded, .today: return []
            case .missed, .upcoming: return [.cannotMarkMissed]
            }
        }
    }

    /// The checks for a move target day, in order: window first, then free.
    static func targetViolations(_ target: LocalDate, plan: TrainingPlan, today: LocalDate) -> [EditViolation] {
        if target < PlanEditRules.earliestTarget(plan: plan, today: today) { return [.targetBeforeEarliest] }
        if target > PlanEditRules.latestTarget(plan: plan) { return [.targetAfterLatest] }
        if plan.session(on: target) != nil { return [.targetOccupied] }
        return []
    }
}

/// The days the Calendar offers while moving or swapping. Pure.
public enum PlanEditTargets {
    /// Every free day from the earliest to the latest target, except the session's
    /// own day. Any weekday counts, not only training days.
    public static func moveTargets(sessionId: String, plan: TrainingPlan, runs: [CompletedRun], today: LocalDate) -> Set<LocalDate> {
        guard let session = plan.session(id: sessionId) else { return [] }
        let earliest = PlanEditRules.earliestTarget(plan: plan, today: today)
        let latest = PlanEditRules.latestTarget(plan: plan)
        guard earliest <= latest else { return [] }
        return Set((0...earliest.days(to: latest)).map { earliest.adding(days: $0) }.filter { day in
            PlanEditValidator.violations(
                plan: plan, runs: runs, today: today, edit: .move(sessionId: sessionId, from: session.date, to: day)
            ).isEmpty
        })
    }

    /// The days of every other session that is today or upcoming.
    public static func swapTargets(sessionId: String, plan: TrainingPlan, runs: [CompletedRun], today: LocalDate) -> Set<LocalDate> {
        guard let session = plan.session(id: sessionId) else { return [] }
        return Set(plan.sessions.filter { other in
            PlanEditValidator.violations(
                plan: plan, runs: runs, today: today,
                edit: .swap(sessionIdA: session.id, sessionIdB: other.id, dateA: session.date, dateB: other.date)
            ).isEmpty
        }.map(\.date))
    }
}
