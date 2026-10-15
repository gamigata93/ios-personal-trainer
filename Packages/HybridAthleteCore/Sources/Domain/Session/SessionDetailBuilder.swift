import Foundation

/// One planned session with everything the plan and the runs say about it.
public struct SessionDetail: Sendable, Equatable {
    public let session: PlannedSession
    public let status: SessionStatus
    /// 1-based plan week.
    public let weekIndex: Int
    public let weeksTotal: Int
    public let phase: PlanPhase
    /// The run that completed it, from `SessionCompletionMatcher`.
    public let matchedRun: CompletedRun?
    /// The shortest run on the same day that completes it.
    public let requiredKm: Double
    /// Done minus planned, when a run matched.
    public let deltaKm: Double?
    /// Whole seconds per km, when a run matched and has a distance.
    public let paceSecPerKm: Int?
}

public enum SessionDetailBuilder {
    /// Nil when `sessionId` is not (or no longer) in the plan.
    public static func build(plan: TrainingPlan, runs: [CompletedRun], sessionId: String, today: LocalDate) -> SessionDetail? {
        guard
            let week = plan.weeks.first(where: { $0.sessions.contains { $0.id == sessionId } }),
            let session = week.sessions.first(where: { $0.id == sessionId })
        else { return nil }
        let progress = PlanProgress(plan: plan, runs: runs, today: today)
        let run = progress.matches[session.id]
        return SessionDetail(
            session: session,
            status: progress.status(of: session),
            weekIndex: week.index,
            weeksTotal: plan.weeks.count,
            phase: week.phase,
            matchedRun: run,
            requiredKm: PlanProgressRules.matchShare * session.distanceKm,
            deltaKm: run.map { $0.distanceKm - session.distanceKm },
            paceSecPerKm: run.flatMap { $0.distanceKm > 0 ? Int(($0.durationSeconds / $0.distanceKm).rounded()) : nil }
        )
    }
}

/// Plain English session detail text. Pure and locale-independent.
public enum SessionFormat {
    /// 360 "6:00 /km", 600 "10:00 /km".
    public static func paceText(secondsPerKm seconds: Int) -> String {
        "\(seconds / 60):\(twoDigits(seconds % 60)) /km"
    }

    /// "42:00" under an hour, "1:05:30" from an hour, "0:59" under a minute.
    public static func runDurationText(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3_600
        let minutes = total % 3_600 / 60
        let rest = total % 60
        return hours > 0 ? "\(hours):\(twoDigits(minutes)):\(twoDigits(rest))" : "\(minutes):\(twoDigits(rest))"
    }

    /// One decimal: "7.0 km".
    public static func distanceText(km: Double) -> String {
        "\(oneDecimal(km)) km"
    }

    /// "+0.2 km", "−3.0 km" (U+2212), or "As planned" under 0.05 km either way.
    /// Tenths round half away from zero, so 0.05 is "+0.1 km".
    public static func deltaKmText(_ delta: Double) -> String {
        guard abs(delta) >= 0.05 - 1e-9 else { return "As planned" }
        let text = oneDecimal(abs(delta))
        return delta > 0 ? "+\(text) km" : "\u{2212}\(text) km"
    }

    /// "Easy", "Tempo", "Threshold", "Intervals", "Long run".
    public static func sessionTypeName(_ type: SessionType) -> String {
        switch type {
        case .easy: "Easy"
        case .tempo: "Tempo"
        case .threshold: "Threshold"
        case .intervals: "Intervals"
        case .long: "Long run"
        }
    }

    /// "Week 3 of 8 · Base phase".
    public static func weekPhaseLine(week: Int, of total: Int, phase: PlanPhase) -> String {
        "Week \(week) of \(total) · \(phase.rawValue.capitalized) phase"
    }

    /// "We look for a run of at least 3.0 km on the same day."
    public static func requiredRunText(requiredKm: Double) -> String {
        "We look for a run of at least \(oneDecimal(requiredKm)) km on the same day."
    }

    /// Tenths, half away from zero: 0.05 "0.1", 7 "7.0".
    static func oneDecimal(_ value: Double) -> String {
        let tenths = Int((value * 10 + (value >= 0 ? 1e-9 : -1e-9)).rounded(.toNearestOrAwayFromZero))
        let sign = tenths < 0 ? "-" : ""
        return "\(sign)\(abs(tenths) / 10).\(abs(tenths) % 10)"
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
