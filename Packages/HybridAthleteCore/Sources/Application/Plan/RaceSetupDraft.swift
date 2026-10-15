import Foundation
import Domain

/// What the race setup screen starts from: a suggested plan with its distance
/// and race day filled in, or a blank custom race. Training days are never prefilled.
public struct RaceSetupDraft: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case suggested(PlanSuggestion)
        case custom
    }

    public let source: Source
    public let distanceKm: Double?
    public let raceDate: LocalDate?
    /// The suggested plan's runs per week, for a soft hint. Never a requirement.
    public let runsPerWeek: Int?

    public static let custom = RaceSetupDraft(source: .custom, distanceKm: nil, raceDate: nil, runsPerWeek: nil)

    public static func suggested(_ suggestion: PlanSuggestion, calendar: Calendar) -> RaceSetupDraft {
        RaceSetupDraft(
            source: .suggested(suggestion),
            distanceKm: raceDistanceKm(suggestion.plan),
            raceDate: suggestion.suggestedRaceDate.map { LocalDate($0, calendar: calendar) },
            runsPerWeek: suggestion.runsPerWeek
        )
    }

    /// The race distance a suggested plan prefills.
    public static func raceDistanceKm(_ plan: PlanKind) -> Double {
        switch plan {
        case .fiveK: 5
        case .tenK: 10
        case .halfMarathon: 21.1
        case .marathon: 42.2
        }
    }

    /// The source as a plan request records it.
    public var planSource: PlanSource {
        switch source {
        case .suggested(let suggestion): .suggested(suggestion.plan)
        case .custom: .custom
        }
    }
}
