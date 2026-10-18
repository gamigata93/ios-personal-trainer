import Foundation
import Domain

/// Everything the strength detail shows, already worded.
public struct StrengthDetail: Sendable, Equatable {
    public struct Exercise: Sendable, Equatable, Identifiable {
        public var id: Int { position }
        public let position: Int
        public let name: String
        /// "3 × 10 per side".
        public let dose: String
        /// "Dumbbell or kettlebell".
        public let equipment: String
        public let howTo: String
    }

    public let sessionID: String
    /// "Strength: Lower body A".
    public let title: String
    /// "Wed 28 Oct · Week 3 · Build phase".
    public let caption: String
    public let status: SessionStatus
    public let statusText: String
    /// "30 min".
    public let minutes: String
    /// "Moderate weight, 2 reps in reserve".
    public let effort: String
    /// "Done: Strength training, 32 min." when a workout completed it.
    public let doneLine: String?
    public let exercises: [Exercise]
}

/// Builds the strength detail for one strength session.
public struct GetStrengthDetail: Sendable {
    private let clock: any Clock
    private let calendar: Calendar

    public init(clock: any Clock, calendar: Calendar) {
        self.clock = clock
        self.calendar = calendar
    }

    public func execute(plan: TrainingPlan, workouts: CompletedRunsResult, sessionID: String) -> StrengthDetail? {
        guard let session = plan.strengthSession(id: sessionID) else { return nil }
        let today = LocalDate(date: clock.now(), calendar: calendar)
        let progress = PlanProgress(plan: plan, runs: workouts.runs, strength: workouts.strength, today: today)
        let status = progress.status(of: session)
        let week = plan.week(containing: session.date)
        let caption = [HomeFormat.shortDate(session.date)]
            + (week.map { ["Week \($0.index)", "\($0.phase.rawValue.capitalized) phase"] } ?? [])
        return StrengthDetail(
            sessionID: session.id,
            title: session.name,
            caption: caption.joined(separator: " · "),
            status: status,
            statusText: HomeFormat.statusText(status),
            minutes: "\(session.minutes) min",
            effort: session.effort,
            doneLine: progress.strengthMatches[session.id].map { "Done: \($0.kind.title), \($0.minutes) min." },
            exercises: session.exercises.enumerated().map { position, exercise in
                StrengthDetail.Exercise(
                    position: position, name: exercise.name, dose: exercise.doseText, equipment: exercise.equipment.title, howTo: exercise.howTo
                )
            }
        )
    }
}
