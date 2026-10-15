import Foundation

/// Which race setup field an issue belongs to.
public enum RaceSetupField: Sendable, Equatable, CaseIterable {
    case raceDay, distance, elevation, trainingDays
}

public enum RaceSetupIssue: Sendable, Equatable {
    case raceTooSoon
    case raceTooFar
    case distanceOutOfRange
    case elevationOutOfRange
    case tooFewDays
    case tooManyDays

    public var message: String {
        switch self {
        case .raceTooSoon: "Pick a race day at least 4 weeks from now."
        case .raceTooFar: "Pick a race day within a year."
        case .distanceOutOfRange: "Enter a distance between 1 and 250 km."
        case .elevationOutOfRange: "Enter 0 to 10,000 m or leave it blank."
        case .tooFewDays: "Choose at least 2 training days."
        case .tooManyDays: "Keep at least one rest day."
        }
    }

    public var field: RaceSetupField {
        switch self {
        case .raceTooSoon, .raceTooFar: .raceDay
        case .distanceOutOfRange: .distance
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
    public static let distanceRange: ClosedRange<Double> = 1...250
    public static let elevationRange: ClosedRange<Double> = 0...10_000
    public static let trainingDayRange: ClosedRange<Int> = 2...6

    public static func issues(_ setup: RaceSetup, today: LocalDate) -> [RaceSetupIssue] {
        var issues: [RaceSetupIssue] = []
        let days = PlanCalendar.inclusiveDays(from: PlanCalendar.planStart(today: today), to: setup.raceDate)
        if days < minimumDays { issues.append(.raceTooSoon) }
        if days > maximumDays { issues.append(.raceTooFar) }
        if !distanceRange.contains(setup.distanceKm) { issues.append(.distanceOutOfRange) }
        if !elevationRange.contains(setup.elevationGainM) { issues.append(.elevationOutOfRange) }
        if setup.trainingDays.count < trainingDayRange.lowerBound { issues.append(.tooFewDays) }
        if setup.trainingDays.count > trainingDayRange.upperBound { issues.append(.tooManyDays) }
        return issues
    }
}
