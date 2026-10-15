import Foundation

/// One change the user makes to the plan. Edits only change dates or the
/// missed flag; ids and content never change.
public enum PlanEdit: Sendable, Equatable, Codable {
    /// Moves a session to a free day. Clears its missed flag.
    case move(sessionId: String, from: LocalDate, to: LocalDate)
    /// Two sessions exchange their dates. `dateA` is A's date before the swap.
    case swap(sessionIdA: String, sessionIdB: String, dateA: LocalDate, dateB: LocalDate)
    /// Acknowledges a session that will not be done.
    case markMissed(sessionId: String)

    /// "move", "swap" or "markMissed", as stored in the edit log.
    public var kind: String {
        switch self {
        case .move: "move"
        case .swap: "swap"
        case .markMissed: "markMissed"
        }
    }

    /// The sessions it touches.
    public var sessionIds: [String] {
        switch self {
        case .move(let id, _, _), .markMissed(let id): [id]
        case .swap(let a, let b, _, _): [a, b]
        }
    }
}

/// Where a session is and whether it is marked missed: everything an edit changes.
public struct SessionPlacement: Sendable, Equatable, Hashable, Codable {
    public let sessionId: String
    public let date: LocalDate
    public let isMissed: Bool

    public init(sessionId: String, date: LocalDate, isMissed: Bool) {
        self.sessionId = sessionId
        self.date = date
        self.isMissed = isMissed
    }

    public init(_ session: PlannedSession) {
        self.init(sessionId: session.id, date: session.date, isMissed: session.isMissed)
    }
}

/// The concrete effect of an edit: the touched sessions before and after.
/// Undo is the inverse change, so a move of a missed session restores its flag too.
public struct PlanChange: Sendable, Equatable, Codable {
    public let before: [SessionPlacement]
    public let after: [SessionPlacement]

    public init(before: [SessionPlacement], after: [SessionPlacement]) {
        self.before = before
        self.after = after
    }

    /// Pure inverse: after becomes before.
    public var inverse: PlanChange {
        PlanChange(before: after, after: before)
    }

    /// The days whose session changed (both old and new dates).
    public var touchedDates: Set<LocalDate> {
        Set(before.map(\.date) + after.map(\.date))
    }

    /// What `edit` does to sessions currently placed as in `current` (by id).
    /// Nil when a session is missing or not where the edit expects (a stale edit).
    public static func make(_ edit: PlanEdit, current: [String: SessionPlacement]) -> PlanChange? {
        switch edit {
        case .move(let id, let from, let to):
            guard let now = current[id], now.date == from else { return nil }
            return PlanChange(before: [now], after: [SessionPlacement(sessionId: id, date: to, isMissed: false)])
        case .swap(let a, let b, let dateA, let dateB):
            guard a != b, let nowA = current[a], let nowB = current[b], nowA.date == dateA, nowB.date == dateB else { return nil }
            return PlanChange(
                before: [nowA, nowB],
                after: [
                    SessionPlacement(sessionId: a, date: dateB, isMissed: nowA.isMissed),
                    SessionPlacement(sessionId: b, date: dateA, isMissed: nowB.isMissed),
                ]
            )
        case .markMissed(let id):
            guard let now = current[id], !now.isMissed else { return nil }
            return PlanChange(before: [now], after: [SessionPlacement(sessionId: id, date: now.date, isMissed: true)])
        }
    }
}

/// Applies edits to a plan in memory. Pure: ids and content never change.
public enum PlanEditApplier {
    /// The plan after `edit`, or nil when the edit does not fit the plan.
    /// Validate with `PlanEditValidator` first.
    public static func apply(_ edit: PlanEdit, to plan: TrainingPlan) -> TrainingPlan? {
        guard let change = PlanChange.make(edit, current: placements(of: plan)) else { return nil }
        return apply(change, to: plan)
    }

    /// The plan with every session in `change.after` placed as described.
    public static func apply(_ change: PlanChange, to plan: TrainingPlan) -> TrainingPlan {
        let byId = Dictionary(change.after.map { ($0.sessionId, $0) }, uniquingKeysWith: { _, last in last })
        return plan.replacingSessions(plan.sessions.map { session in
            byId[session.id].map { session.placed(on: $0.date, isMissed: $0.isMissed) } ?? session
        })
    }

    /// Session id -> where it is now.
    public static func placements(of plan: TrainingPlan) -> [String: SessionPlacement] {
        Dictionary(plan.sessions.map { ($0.id, SessionPlacement($0)) }, uniquingKeysWith: { first, _ in first })
    }
}
