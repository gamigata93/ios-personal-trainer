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
    /// The model decides how many (0 to `StrengthRules.maxPerWeek`).
    public let strength: [DraftStrength]

    public init(index: Int, phase: PlanPhase, sessions: [DraftSession], strength: [DraftStrength] = []) {
        self.index = index
        self.phase = phase
        self.sessions = sessions
        self.strength = strength
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

/// One strength session as a model drafts it: code fills the exercises.
public struct DraftStrength: Sendable, Equatable, Codable {
    public let weekday: Weekday
    public let focus: StrengthFocus
    public let minutes: Int

    public init(weekday: Weekday, focus: StrengthFocus, minutes: Int) {
        self.weekday = weekday
        self.focus = focus
        self.minutes = minutes
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
    case tooManyStrength(week: Int)
    case duplicateStrengthDay(week: Int, weekday: Weekday)
    case strengthMinutes(week: Int)
    case strengthPlacement(week: Int, weekday: Weekday, StrengthPlacement.Problem)

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
        case .tooManyStrength(let week): "Week \(week) has more than \(StrengthRules.maxPerWeek) strength sessions."
        case .duplicateStrengthDay(let week, let weekday): "Week \(week) has two strength sessions on \(weekday.name)."
        case .strengthMinutes(let week):
            "Week \(week) has a strength session outside \(StrengthRules.minutesRange.lowerBound) to \(StrengthRules.minutesRange.upperBound) minutes."
        case .strengthPlacement(let week, let weekday, let problem):
            "Week \(week) has strength on \(weekday.name), \(problem.reason)."
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
        violations += strengthViolations(draft, request: request)
        return violations
    }

    /// Strength count, minutes, one a day, and placement against the drafted runs.
    static func strengthViolations(_ draft: PlanDraft, request: PlanRequest) -> [DraftViolation] {
        var violations: [DraftViolation] = []
        let start = request.planStart
        var runs: [LocalDate: SessionType] = [:]
        for week in draft.weeks {
            let weekStart = start.adding(days: 7 * (week.index - 1))
            for session in week.sessions { runs[weekStart.adding(days: session.weekday.index)] = session.type }
        }
        for week in draft.weeks {
            if week.strength.count > StrengthRules.maxPerWeek { violations.append(.tooManyStrength(week: week.index)) }
            var seen: Set<Weekday> = []
            let weekStart = start.adding(days: 7 * (week.index - 1))
            for item in week.strength {
                if !seen.insert(item.weekday).inserted {
                    violations.append(.duplicateStrengthDay(week: week.index, weekday: item.weekday))
                }
                if !StrengthRules.minutesRange.contains(item.minutes) { violations.append(.strengthMinutes(week: week.index)) }
                let problems = StrengthPlacement.problems(
                    date: weekStart.adding(days: item.weekday.index), runs: runs, trainingDays: request.race.trainingDays,
                    raceDate: request.race.raceDate, planStart: start
                )
                violations += problems.map { .strengthPlacement(week: week.index, weekday: item.weekday, $0) }
            }
        }
        return violations
    }
}

extension StrengthPlacement.Problem {
    /// "which is not a training day".
    public var reason: String {
        switch self {
        case .notATrainingDay: "which is not a training day"
        case .onHardRunDay: "the same day as a tempo, threshold, interval or long run"
        case .dayBeforeLongRun: "the day before a long run"
        case .inRaceWeek: "in race week"
        case .outsideWindow: "outside the plan (from the start to 2 days before race day)"
        case .twoOnOneDay: "where there is already a strength session"
        }
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
            return PlanWeek(index: week.index, startDate: weekStart, phase: week.phase, targetKm: week.totalKm, sessions: sessions, strength: [])
        }
        let drafted = zip(draft.weeks, weeks).flatMap { draftWeek, week in
            draftWeek.strength.map { (date: week.startDate.adding(days: $0.weekday.index), item: $0, phase: week.phase) }
        }
        let variants = StrengthContentBuilder.variants(for: drafted.map { ($0.date, $0.item.focus) })
        let strength = drafted.map { entry in
            StrengthContentBuilder.session(
                date: entry.date, focus: entry.item.focus, minutes: entry.item.minutes, phase: entry.phase,
                variant: variants[entry.date] ?? .a
            )
        }
        return TrainingPlan(
            id: "",
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            generatedBy: generatedBy,
            planKind: request.planKind,
            race: request.race,
            planStart: start,
            weeks: weeks
        ).replacing(sessions: weeks.flatMap(\.sessions), strength: strength)
    }
}
