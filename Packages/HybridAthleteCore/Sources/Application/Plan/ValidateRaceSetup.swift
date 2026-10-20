import Foundation
import Domain

/// The race setup issues as of today.
public struct ValidateRaceSetup: Sendable {
    private let clock: any Clock
    private let calendar: Calendar
    private let scope: RaceDistanceScope

    public init(clock: any Clock, calendar: Calendar, scope: RaceDistanceScope = .app) {
        self.clock = clock
        self.calendar = calendar
        self.scope = scope
    }

    /// `parsedDistanceKm`: the distance field as parsed (nil = blank or unreadable).
    public func execute(_ setup: RaceSetup, parsedDistanceKm: Decimal?? = .none) -> [RaceSetupIssue] {
        RaceSetupValidator.issues(setup, today: LocalDate(clock.now(), calendar: calendar), parsedDistanceKm: parsedDistanceKm, scope: scope)
    }

    /// Today, for date pickers.
    public var today: LocalDate { LocalDate(clock.now(), calendar: calendar) }
}
