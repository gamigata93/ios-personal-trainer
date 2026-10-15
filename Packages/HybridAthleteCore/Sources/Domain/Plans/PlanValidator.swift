import Foundation

/// A way a generated plan breaks the rules. Every generator's output is checked,
/// including future LLM output, before anything is saved.
public enum PlanViolation: Sendable, Equatable {
    case noSessions
    case sessionOutsideWindow(LocalDate)
    case sessionOnRestDay(LocalDate)
    case twoSessionsOnOneDay(LocalDate)
    case tooManySessionsInWeek(week: Int)
    case sessionOutsideItsWeek(LocalDate)
    case badDistance(LocalDate)
    case longRunOverCap(LocalDate)
    case phasesOutOfOrder(week: Int)
    case lastWeekNotTaper
    case weekGrowsTooFast(week: Int)
}

extension PlanViolation {
    /// A readable sentence, also used as a revision note for a model's next attempt.
    public var message: String {
        switch self {
        case .noSessions: "The plan has no sessions."
        case .sessionOutsideWindow(let date):
            "The session on \(date) is outside the plan: sessions run from the plan start to 2 days before race day."
        case .sessionOnRestDay(let date): "The session on \(date) is on a day that is not a training day."
        case .twoSessionsOnOneDay(let date): "There are two sessions on \(date)."
        case .tooManySessionsInWeek(let week): "Week \(week) has more sessions than training days."
        case .sessionOutsideItsWeek(let date): "The session on \(date) is not inside its week."
        case .badDistance(let date): "The session on \(date) has a distance that is zero, negative or over 60 km."
        case .longRunOverCap(let date): "The long run on \(date) is over the long run cap."
        case .phasesOutOfOrder(let week): "Week \(week) goes back to an earlier phase."
        case .lastWeekNotTaper: "The last week must be a taper week."
        case .weekGrowsTooFast(let week): "Week \(week) grows more than 25% over the larger of the two weeks before."
        }
    }
}

public enum PlanValidator {
    public static let maxSessionKm = 60.0
    /// Week totals may grow to this multiple of the larger of the two weeks before.
    public static let maxWeeklyGrowth = 1.25
    /// The reference before week 1 is max(baseline weekly km, this).
    public static let minimumReferenceKm = 10.0
    /// The last session may be this many days before race day at the latest.
    public static let daysClearBeforeRace = 2

    public static func longRunCapKm(_ kind: PlanKind) -> Double {
        switch kind {
        case .fiveK: 14
        case .tenK: 18
        case .halfMarathon: 24
        case .marathon: 32
        }
    }

    public static func violations(_ plan: TrainingPlan, request: PlanRequest) -> [PlanViolation] {
        var violations: [PlanViolation] = []
        let sessions = plan.sessions
        if sessions.isEmpty { violations.append(.noSessions) }

        // 1-4: each session's day and distance.
        let lastDay = request.race.raceDate.adding(days: -daysClearBeforeRace)
        let cap = longRunCapKm(request.planKind)
        var seenDays: Set<LocalDate> = []
        for session in sessions {
            if session.date < request.planStart || session.date > lastDay {
                violations.append(.sessionOutsideWindow(session.date))
            }
            if !request.race.trainingDays.contains(session.date.weekday) {
                violations.append(.sessionOnRestDay(session.date))
            }
            if !seenDays.insert(session.date).inserted {
                violations.append(.twoSessionsOnOneDay(session.date))
            }
            if !(session.distanceKm > 0) || session.distanceKm > maxSessionKm {
                violations.append(.badDistance(session.date))
            }
            if session.type == .long && session.distanceKm > cap {
                violations.append(.longRunOverCap(session.date))
            }
        }

        // 3: sessions per week, and each in its own week.
        for week in plan.weeks {
            if week.sessions.count > request.race.trainingDays.count {
                violations.append(.tooManySessionsInWeek(week: week.index))
            }
            for session in week.sessions where session.date < week.startDate || session.date > week.startDate.adding(days: 6) {
                violations.append(.sessionOutsideItsWeek(session.date))
            }
        }

        // 5: phases never go backwards and the plan ends in a taper.
        for (previous, next) in zip(plan.weeks, plan.weeks.dropFirst()) where next.phase < previous.phase {
            violations.append(.phasesOutOfOrder(week: next.index))
        }
        if let last = plan.weeks.last, last.phase != .taper {
            violations.append(.lastWeekNotTaper)
        }

        // 6: weekly totals grow at most 25% over the larger of the two weeks before.
        let reference = max(request.fitness.weeklyKm, minimumReferenceKm)
        var previousTotals = [reference, reference]
        for week in plan.weeks {
            let total = week.totalKm
            if total > maxWeeklyGrowth * max(previousTotals[0], previousTotals[1]) + 1e-9 {
                violations.append(.weekGrowsTooFast(week: week.index))
            }
            previousTotals = [previousTotals[1], total]
        }
        return violations
    }
}
