import Foundation
import Domain

/// One planned session, worded for the session detail screen. Only what the
/// plan and the runs contain.
public struct SessionDetailOverview: Sendable, Equatable {
    public struct Segment: Sendable, Equatable, Identifiable {
        /// 1-based.
        public let number: Int
        public var id: Int { number }
        public let label: String
        public let detail: String
        /// "3.0 km", or nil when the segment has no distance.
        public let distance: String?
        /// "Segment 2, Threshold, 3 x 8 min at threshold, 3 kilometres".
        public let accessibilityLabel: String
    }

    /// What the runs say about the session.
    public enum Result: Sendable, Equatable {
        /// "7.0 km", "42:00", "6:00 /km" and "Planned 10.0 km · −3.0 km".
        case completed(distance: String, duration: String, pace: String?, plannedLine: String)
        /// "We look for a run of at least 3.0 km on the same day."
        case notRecorded(requiredRunText: String)
        /// The user marked it as missed.
        case missed
    }

    public let id: String
    /// "Today's session", "Upcoming session" or "Session".
    public let caption: String
    /// "Wednesday, 28 October".
    public let dateText: String
    public let name: String
    public let type: SessionType
    /// "Easy", "Long run".
    public let typeName: String
    public let status: SessionStatus
    /// "Completed", "Today".
    public let statusText: String
    /// "Week 3 of 8 · Base phase".
    public let weekPhaseLine: String
    /// "Moved from Mon 26 Oct" when an edit put it on another day.
    public let movedFrom: String?
    /// "7.5 km" (one decimal).
    public let distance: String
    /// "Distance 7.5 kilometres".
    public let distanceAccessibilityLabel: String
    /// "~40 min", or "—" without an estimate.
    public let estimatedTime: String
    public let effort: String
    /// Nil for today and upcoming sessions.
    public let result: Result?
    public let segments: [Segment]
    public let note: String?
}

/// Finds a session in the plan by id and words it with its status and run.
public struct GetSessionDetail: Sendable {
    private let clock: any Clock
    private let calendar: Calendar

    public init(clock: any Clock, calendar: Calendar) {
        self.clock = clock
        self.calendar = calendar
    }

    /// Nil when the session is no longer in the plan.
    public func execute(plan: TrainingPlan, runs: [CompletedRun], sessionID: String) -> SessionDetailOverview? {
        let today = LocalDate(date: clock.now(), calendar: calendar)
        guard let detail = SessionDetailBuilder.build(plan: plan, runs: runs, sessionId: sessionID, today: today) else { return nil }
        let session = detail.session
        let distance = SessionFormat.distanceText(km: session.distanceKm)

        let result: SessionDetailOverview.Result?
        switch detail.status {
        case .completed:
            if let run = detail.matchedRun, let delta = detail.deltaKm {
                result = .completed(
                    distance: SessionFormat.distanceText(km: run.distanceKm),
                    duration: SessionFormat.runDurationText(seconds: run.durationSeconds),
                    pace: detail.paceSecPerKm.map(SessionFormat.paceText(secondsPerKm:)),
                    plannedLine: "Planned \(distance) · \(SessionFormat.deltaKmText(delta))"
                )
            } else {
                result = nil
            }
        case .notRecorded:
            result = .notRecorded(requiredRunText: SessionFormat.requiredRunText(requiredKm: detail.requiredKm))
        case .missed:
            result = .missed
        case .today, .upcoming:
            result = nil
        }

        return SessionDetailOverview(
            id: session.id,
            caption: session.date == today ? "Today's session" : (session.date > today ? "Upcoming session" : "Session"),
            dateText: HomeFormat.longDate(session.date),
            name: session.name,
            type: session.type,
            typeName: SessionFormat.sessionTypeName(session.type),
            status: detail.status,
            statusText: HomeFormat.statusText(detail.status),
            weekPhaseLine: SessionFormat.weekPhaseLine(week: detail.weekIndex, of: detail.weeksTotal, phase: detail.phase),
            movedFrom: PlanEditFormat.movedFrom(session),
            distance: distance,
            distanceAccessibilityLabel: "Distance \(Self.spokenKm(session.distanceKm))",
            estimatedTime: HomeFormat.estimatedTime(minutes: session.estimatedMinutes) ?? "\u{2014}",
            effort: session.effort,
            result: result,
            segments: session.segments.enumerated().map { index, segment in
                let parts = ["Segment \(index + 1)", segment.label, segment.detail] + (segment.distanceKm.map { [Self.spokenKm($0)] } ?? [])
                return SessionDetailOverview.Segment(
                    number: index + 1,
                    label: segment.label,
                    detail: segment.detail,
                    distance: segment.distanceKm.map { SessionFormat.distanceText(km: $0) },
                    accessibilityLabel: parts.filter { !$0.isEmpty }.joined(separator: ", ")
                )
            },
            note: session.note.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    /// "7.5 kilometres", "1 kilometre".
    private static func spokenKm(_ km: Double) -> String {
        let text = HomeFormat.km(km)
        return text == "1" ? "1 kilometre" : "\(text) kilometres"
    }
}
