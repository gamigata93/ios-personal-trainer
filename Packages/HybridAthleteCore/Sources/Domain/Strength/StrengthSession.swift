import Foundation

/// What a strength session trains. The LLM (or the template) picks the focus;
/// code fills the exercises from `StrengthLibrary`.
public enum StrengthFocus: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case lowerBody, calvesFeet, core, fullBody, mobility

    /// "Lower body".
    public var title: String {
        switch self {
        case .lowerBody: "Lower body"
        case .calvesFeet: "Calves and feet"
        case .core: "Core"
        case .fullBody: "Full body"
        case .mobility: "Mobility"
        }
    }

    /// The words a model sees and answers with ("lower body").
    public var promptName: String { title.lowercased() }

    public init?(promptName: String) {
        guard let focus = Self.allCases.first(where: { $0.promptName == promptName.lowercased() }) else { return nil }
        self = focus
    }
}

/// Which of a focus's two fixed lists a session uses. Sessions of the same focus
/// alternate A, B, A, ... in date order across the plan.
public enum StrengthVariant: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case a = "A", b = "B"

    /// The variant of the `occurrence`-th session (0-based) of a focus.
    public static func of(occurrence: Int) -> StrengthVariant { occurrence % 2 == 0 ? .a : .b }
}

/// What an exercise needs.
public enum StrengthEquipment: String, Sendable, Equatable, Codable, CaseIterable {
    case bodyweight, dumbbell, band

    public var title: String {
        switch self {
        case .bodyweight: "Bodyweight"
        case .dumbbell: "Dumbbell or kettlebell"
        case .band: "Band"
        }
    }
}

/// One exercise as prescribed in a session: the dose is already set for the phase.
public struct StrengthExercise: Sendable, Equatable, Codable {
    public let name: String
    public let sets: Int
    /// Repetitions per set; nil for a timed hold.
    public let reps: Int?
    /// Seconds per set for a hold; nil for repetitions.
    public let seconds: Int?
    /// Reps or seconds are per leg, arm or side.
    public let perSide: Bool
    public let equipment: StrengthEquipment
    /// One line on how to do it.
    public let howTo: String

    public init(name: String, sets: Int, reps: Int?, seconds: Int?, perSide: Bool, equipment: StrengthEquipment, howTo: String) {
        self.name = name
        self.sets = sets
        self.reps = reps
        self.seconds = seconds
        self.perSide = perSide
        self.equipment = equipment
        self.howTo = howTo
    }

    /// "3 × 10 per side", "2 × 30 s".
    public var doseText: String {
        let amount = reps.map(String.init) ?? seconds.map { "\($0) s" } ?? ""
        return "\(sets) \u{00D7} \(amount)" + (perSide ? " per side" : "")
    }
}

/// One planned strength session. Like a run, its id is its ORIGINAL date (with
/// a "strength-" prefix, so it never collides with a run on the same day), its
/// status is derived, and only the "missed" acknowledgement is stored.
public struct StrengthSession: Sendable, Equatable, Codable {
    public static let idPrefix = "strength-"

    public let id: String
    public let originalDate: LocalDate
    public let date: LocalDate
    public let focus: StrengthFocus
    public let variant: StrengthVariant
    public let minutes: Int
    /// The phase's load cue ("Moderate weight, 2 reps in reserve").
    public let effort: String
    public let exercises: [StrengthExercise]
    public let isMissed: Bool

    public init(
        id: String, originalDate: LocalDate, date: LocalDate, focus: StrengthFocus, variant: StrengthVariant, minutes: Int,
        effort: String, exercises: [StrengthExercise], isMissed: Bool
    ) {
        self.id = id
        self.originalDate = originalDate
        self.date = date
        self.focus = focus
        self.variant = variant
        self.minutes = minutes
        self.effort = effort
        self.exercises = exercises
        self.isMissed = isMissed
    }

    /// "Strength: Lower body A".
    public var name: String { "Strength: \(focus.title) \(variant.rawValue)" }

    public static func id(for date: LocalDate) -> String { idPrefix + date.description }

    public static func isStrengthId(_ id: String) -> Bool { id.hasPrefix(idPrefix) }
}
