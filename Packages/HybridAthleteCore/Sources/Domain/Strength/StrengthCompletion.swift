import Foundation

/// The kinds of Health workout that complete a strength session.
public enum StrengthWorkoutKind: String, Sendable, Equatable, Codable, CaseIterable {
    case traditionalStrength, functionalStrength, core, hiit

    /// "Strength training".
    public var title: String {
        switch self {
        case .traditionalStrength: "Strength training"
        case .functionalStrength: "Functional strength"
        case .core: "Core training"
        case .hiit: "HIIT"
        }
    }
}

/// One strength, core or HIIT workout as the health source reports it.
public struct StrengthWorkoutSummary: Sendable, Equatable {
    /// The health store's workout UUID.
    public let id: String
    public let startDate: Date
    public let durationSeconds: Double
    public let kind: StrengthWorkoutKind

    public init(id: String, startDate: Date, durationSeconds: Double, kind: StrengthWorkoutKind) {
        self.id = id
        self.startDate = startDate
        self.durationSeconds = durationSeconds
        self.kind = kind
    }
}

/// A strength workout placed on its local day (kept in the runs cache).
public struct CompletedStrength: Sendable, Equatable, Codable {
    public let id: String
    public let localDate: LocalDate
    public let durationSeconds: Double
    public let kind: StrengthWorkoutKind

    public init(id: String, localDate: LocalDate, durationSeconds: Double, kind: StrengthWorkoutKind) {
        self.id = id
        self.localDate = localDate
        self.durationSeconds = durationSeconds
        self.kind = kind
    }

    public var minutes: Int { Int((durationSeconds / 60).rounded()) }
}

/// Matches strength workouts to strength sessions: same local day, at least
/// `StrengthRules.minimumWorkoutMinutes` long; the longest wins and a workout
/// completes one session at most (there is at most one strength session a day).
public enum StrengthCompletionMatcher {
    public static func match(sessions: [StrengthSession], workouts: [CompletedStrength]) -> [String: CompletedStrength] {
        var result: [String: CompletedStrength] = [:]
        let qualifying = workouts.filter { $0.durationSeconds >= StrengthRules.minimumWorkoutMinutes * 60 - 1e-9 }
        for session in sessions {
            let best = qualifying
                .filter { $0.localDate == session.date }
                .max { ($0.durationSeconds, $1.id) < ($1.durationSeconds, $0.id) }
            if let best { result[session.id] = best }
        }
        return result
    }
}
