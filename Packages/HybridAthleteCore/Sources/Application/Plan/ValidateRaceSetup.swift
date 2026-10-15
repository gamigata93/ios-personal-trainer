import Foundation
import Domain

/// The race setup issues as of today.
public struct ValidateRaceSetup: Sendable {
    private let clock: any Clock
    private let calendar: Calendar

    public init(clock: any Clock, calendar: Calendar) {
        self.clock = clock
        self.calendar = calendar
    }

    public func execute(_ setup: RaceSetup) -> [RaceSetupIssue] {
        RaceSetupValidator.issues(setup, today: LocalDate(clock.now(), calendar: calendar))
    }

    /// Today, for date pickers.
    public var today: LocalDate { LocalDate(clock.now(), calendar: calendar) }
}
