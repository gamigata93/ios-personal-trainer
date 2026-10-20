import Foundation

/// Which race setup field an issue belongs to.
public enum RaceSetupField: Sendable, Equatable, CaseIterable {
    case raceDay, distance, elevation, trainingDays
}

public enum RaceSetupIssue: Sendable, Equatable {
    case raceTooSoon
    case raceTooFar
    /// Blank or unreadable.
    case distanceMissing
    /// Outside 5 km to a full marathon (`AppScope`).
    case distanceOutOfScope
    case elevationOutOfRange
    case tooFewDays
    case tooManyDays

    public var message: String {
        switch self {
        case .raceTooSoon: "Pick a race day at least 4 weeks from now."
        case .raceTooFar: "Pick a race day within a year."
        case .distanceMissing: "Enter a race distance."
        case .distanceOutOfScope: "Pick a race distance from 5 km up to a full marathon (42.195 km)."
        case .elevationOutOfRange: "Enter 0 to 10,000 m or leave it blank."
        case .tooFewDays: "Choose at least 2 training days."
        case .tooManyDays: "Keep at least one rest day."
        }
    }

    public var field: RaceSetupField {
        switch self {
        case .raceTooSoon, .raceTooFar: .raceDay
        case .distanceMissing, .distanceOutOfScope: .distance
        case .elevationOutOfRange: .elevation
        case .tooFewDays, .tooManyDays: .trainingDays
        }
    }
}

/// Checks a race setup before a plan is built. Issues come in field order.
public enum RaceSetupValidator {
    /// At least 4 weeks (28 days, plan start and race day included).
    public static let minimumDays = 28
    /// At most 52 weeks (364 days).
    public static let maximumDays = 364
    public static let elevationRange: ClosedRange<Double> = 0...10_000
    public static let trainingDayRange: ClosedRange<Int> = 2...6

    /// `distanceKm` overrides the setup's distance when the field was parsed separately:
    /// nil there means blank or unreadable. `scope` is the app's unless DEBUG widens it.
    public static func issues(
        _ setup: RaceSetup, today: LocalDate, parsedDistanceKm: Decimal?? = .none, scope: RaceDistanceScope = .app
    ) -> [RaceSetupIssue] {
        var issues: [RaceSetupIssue] = []
        let days = PlanCalendar.inclusiveDays(from: PlanCalendar.planStart(today: today), to: setup.raceDate)
        if days < minimumDays { issues.append(.raceTooSoon) }
        if days > maximumDays { issues.append(.raceTooFar) }
        if let issue = distanceIssue(parsedDistanceKm ?? Decimal.exact(setup.distanceKm), scope: scope) { issues.append(issue) }
        if !elevationRange.contains(setup.elevationGainM) { issues.append(.elevationOutOfRange) }
        if setup.trainingDays.count < trainingDayRange.lowerBound { issues.append(.tooFewDays) }
        if setup.trainingDays.count > trainingDayRange.upperBound { issues.append(.tooManyDays) }
        return issues
    }

    /// Blank or unreadable (nil): missing. Outside the scope: out of scope.
    public static func distanceIssue(_ distanceKm: Decimal?, scope: RaceDistanceScope = .app) -> RaceSetupIssue? {
        guard let distanceKm else { return .distanceMissing }
        return scope.contains(distanceKm) ? nil : .distanceOutOfScope
    }
}
