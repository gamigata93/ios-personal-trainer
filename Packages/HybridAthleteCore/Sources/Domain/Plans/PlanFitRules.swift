import Foundation

/// The training plans the app can suggest.
public enum PlanKind: String, Sendable, Equatable, CaseIterable {
    case fiveK
    case tenK
    case halfMarathon
    case marathon
}

/// Every constant behind plan suggestions and their fit labels, in one place.
/// These are proposals; change them here only.
public enum PlanFitRules {
    public struct Requirement: Sendable, Equatable {
        public let minWeeklyKm: Double
        public let minLongestKm: Double
        public let weeks: Int
        public let runsPerWeek: Int
    }

    /// Smallest plan first.
    public static let plans: [PlanKind] = [.fiveK, .tenK, .halfMarathon, .marathon]

    public static func requirement(for plan: PlanKind) -> Requirement {
        switch plan {
        case .fiveK: Requirement(minWeeklyKm: 10, minLongestKm: 4, weeks: 6, runsPerWeek: 3)
        case .tenK: Requirement(minWeeklyKm: 15, minLongestKm: 8, weeks: 8, runsPerWeek: 3)
        case .halfMarathon: Requirement(minWeeklyKm: 25, minLongestKm: 13, weeks: 12, runsPerWeek: 4)
        case .marathon: Requirement(minWeeklyKm: 40, minLongestKm: 21, weeks: 16, runsPerWeek: 4)
        }
    }

    /// Readiness at or above this is a fit.
    public static let fitReadiness = 1.0
    /// Readiness at or above this (and below a fit) is a stretch.
    public static let stretchReadiness = 0.7
    /// Running volume is measured over this many days before now.
    public static let volumeWindowDays = 28
}
