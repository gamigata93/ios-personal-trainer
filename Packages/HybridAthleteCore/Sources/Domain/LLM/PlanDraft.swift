import Foundation

/// A plan's structure as a model drafts it: no dates, no details. Code turns it
/// into a `TrainingPlan` with `PlanDraftExpander`.
public struct PlanDraft: Sendable, Equatable, Codable {
    public let weeks: [DraftWeek]

    public init(weeks: [DraftWeek]) {
        self.weeks = weeks
    }
}

public struct DraftWeek: Sendable, Equatable, Codable {
    /// 1-based.
    public let index: Int
    public let phase: PlanPhase
    public let sessions: [DraftSession]

    public init(index: Int, phase: PlanPhase, sessions: [DraftSession]) {
        self.index = index
        self.phase = phase
        self.sessions = sessions
    }

    public var totalKm: Double { sessions.map(\.distanceKm).reduce(0, +) }
}

public struct DraftSession: Sendable, Equatable, Codable {
    public let weekday: Weekday
    public let type: SessionType
    public let distanceKm: Double

    public init(weekday: Weekday, type: SessionType, distanceKm: Double) {
        self.weekday = weekday
        self.type = type
        self.distanceKm = distanceKm
    }
}

/// Why a draft cannot be expanded. Messages double as revision notes.
public enum DraftViolation: Sendable, Equatable {
    case wrongWeekCount(expected: Int, got: Int)
    case weekIndexOrder
    case weekdayNotAllowed(week: Int, weekday: Weekday)
    case duplicateWeekday(week: Int, weekday: Weekday)
    case nonPositiveDistance(week: Int)
    case phaseOrder(week: Int)
    case lastWeekNotTaper
    case noSessions

    public var message: String {
        switch self {
        case .wrongWeekCount(let expected, let got): "The plan needs exactly \(expected) weeks, not \(got)."
        case .weekIndexOrder: "Number the weeks 1, 2, 3 and so on, in order."
        case .weekdayNotAllowed(let week, let weekday): "Week \(week) uses \(weekday.name), which is not a training day."
        case .duplicateWeekday(let week, let weekday): "Week \(week) has two sessions on \(weekday.name)."
        case .nonPositiveDistance(let week): "Week \(week) has a session with a distance of 0 km or less."
        case .phaseOrder(let week): "Week \(week) goes back to an earlier phase (the order is base, build, peak, taper)."
        case .lastWeekNotTaper: "The last week must be a taper week."
        case .noSessions: "The plan has no sessions."
        }
    }
}

/// Checks a draft's shape before it is expanded. Pure.
public enum PlanDraftValidator {
    public static func violations(_ draft: PlanDraft, request: PlanRequest) -> [DraftViolation] {
        var violations: [DraftViolation] = []
        let expected = request.weekCount
        if draft.weeks.count != expected {
            violations.append(.wrongWeekCount(expected: expected, got: draft.weeks.count))
        }
        if draft.weeks.map(\.index) != Array(draft.weeks.indices.map { $0 + 1 }) {
            violations.append(.weekIndexOrder)
        }
        for week in draft.weeks {
            var seen: Set<Weekday> = []
            for session in week.sessions {
                if !request.race.trainingDays.contains(session.weekday) {
                    violations.append(.weekdayNotAllowed(week: week.index, weekday: session.weekday))
                }
                if !seen.insert(session.weekday).inserted {
                    violations.append(.duplicateWeekday(week: week.index, weekday: session.weekday))
                }
                if !(session.distanceKm > 0) {
                    violations.append(.nonPositiveDistance(week: week.index))
                }
            }
        }
        for (previous, next) in zip(draft.weeks, draft.weeks.dropFirst()) where next.phase < previous.phase {
            violations.append(.phaseOrder(week: next.index))
        }
        if let last = draft.weeks.last, last.phase != .taper {
            violations.append(.lastWeekNotTaper)
        }
        if draft.weeks.allSatisfy({ $0.sessions.isEmpty }) {
            violations.append(.noSessions)
        }
        return violations
    }
}

/// Turns a draft into a dated plan. Never repairs anything: `PlanValidator`
/// runs on the result afterwards.
public enum PlanDraftExpander {
    /// Week n starts at planStart + 7 x (n - 1); each session falls on its weekday
    /// in that week. Ids are the dates ("YYYY-MM-DD"); details come from
    /// `SessionContentBuilder`; each week's target is the sum of its sessions.
    /// The plan id and creation date are placeholders that `CreatePlan` stamps.
    public static func expand(_ draft: PlanDraft, request: PlanRequest, generatedBy: String) -> TrainingPlan {
        let start = request.planStart
        let weeks = draft.weeks.map { week -> PlanWeek in
            let weekStart = start.adding(days: 7 * (week.index - 1))
            let sessions = week.sessions
                .sorted { $0.weekday < $1.weekday }
                .map { draft in
                    SessionContentBuilder.session(
                        date: weekStart.adding(days: draft.weekday.index),
                        type: draft.type,
                        distanceKm: draft.distanceKm,
                        phase: week.phase,
                        kind: request.planKind,
                        race: request.race,
                        avgPaceSecPerKm: request.fitness.avgPaceSecPerKm
                    )
                }
            return PlanWeek(index: week.index, startDate: weekStart, phase: week.phase, targetKm: week.totalKm, sessions: sessions)
        }
        return TrainingPlan(
            id: "",
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            generatedBy: generatedBy,
            planKind: request.planKind,
            race: request.race,
            planStart: start,
            weeks: weeks
        )
    }
}
