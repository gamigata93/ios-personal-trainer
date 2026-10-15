import Foundation

/// One thing the user can do with the selected session.
public struct PlanAction: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case moveNextDay
        case moveAnotherDay
        case swap
        case markMissed
    }

    public let kind: Kind
    /// "Move to next day".
    public let label: String
    /// "Thu 29 Oct is free".
    public let hint: String
    public let isEnabled: Bool
    /// The day a next-day move goes to.
    public let target: LocalDate?

    public init(kind: Kind, label: String, hint: String, isEnabled: Bool, target: LocalDate? = nil) {
        self.kind = kind
        self.label = label
        self.hint = hint
        self.isEnabled = isEnabled
        self.target = target
    }
}

/// Which edit actions a session offers, by its status. Pure.
public enum PlanActions {
    public static func available(session: PlannedSession, plan: TrainingPlan, runs: [CompletedRun], today: LocalDate) -> [PlanAction] {
        let progress = PlanProgress(plan: plan, runs: runs, today: today)
        let status = progress.status(of: session)
        let hasMoveTarget = !PlanEditTargets.moveTargets(sessionId: session.id, plan: plan, runs: runs, today: today).isEmpty
        switch status {
        case .completed:
            return []
        case .today, .upcoming:
            let hasSwap = !PlanEditTargets.swapTargets(sessionId: session.id, plan: plan, runs: runs, today: today).isEmpty
            var actions = [
                nextDay(session, plan: plan, today: today),
                PlanAction(kind: .moveAnotherDay, label: "Move to another day\u{2026}", hint: "Pick any free day", isEnabled: hasMoveTarget),
                PlanAction(kind: .swap, label: "Swap with another session\u{2026}", hint: "Trade places with an upcoming session", isEnabled: hasSwap),
            ]
            if status == .today {
                actions.append(PlanAction(kind: .markMissed, label: "Mark as missed", hint: "Skip today's session", isEnabled: true))
            }
            return actions
        case .notRecorded, .missed:
            var actions = [
                PlanAction(kind: .moveAnotherDay, label: "Move forward to another day\u{2026}", hint: "Pick any free day", isEnabled: hasMoveTarget),
            ]
            if status == .notRecorded {
                actions.append(PlanAction(kind: .markMissed, label: "Mark as missed", hint: "Acknowledge it and move on", isEnabled: true))
            }
            return actions
        }
    }

    /// The day after the session: "is free", "already has a session" or "is too close to race day".
    private static func nextDay(_ session: PlannedSession, plan: TrainingPlan, today: LocalDate) -> PlanAction {
        let target = session.date.adding(days: 1)
        let day = HomeFormat.shortDate(target)
        let violations = PlanEditValidator.targetViolations(target, plan: plan, today: today)
        let hint: String
        if violations.contains(.targetAfterLatest) {
            hint = "\(day) is too close to race day"
        } else if violations.contains(.targetOccupied) {
            hint = "\(day) already has a session"
        } else {
            hint = "\(day) is free"
        }
        return PlanAction(kind: .moveNextDay, label: "Move to next day", hint: hint, isEnabled: violations.isEmpty, target: target)
    }
}
