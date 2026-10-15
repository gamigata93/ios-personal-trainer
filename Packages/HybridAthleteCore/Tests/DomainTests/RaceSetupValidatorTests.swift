import Foundation
import Testing
import Domain

struct RaceSetupValidatorTests {
    /// Fri 9 Oct 2026; plan start Mon 12 Oct.
    private let today = LocalDate(year: 2026, month: 10, day: 9)
    private let start = LocalDate(year: 2026, month: 10, day: 12)

    private func issues(
        daysInclusive: Int = 56,
        km: Double = 10,
        gain: Double = 0,
        days: Set<Weekday> = [.tuesday, .sunday]
    ) -> [RaceSetupIssue] {
        let setup = RaceSetup(distanceKm: km, elevationGainM: gain, raceDate: start.adding(days: daysInclusive - 1), trainingDays: days)
        return RaceSetupValidator.issues(setup, today: today)
    }

    @Test func validSetupHasNoIssues() {
        #expect(issues().isEmpty)
    }

    @Test func raceDayBoundaries() {
        #expect(issues(daysInclusive: 27) == [.raceTooSoon])
        #expect(issues(daysInclusive: 28).isEmpty)
        #expect(issues(daysInclusive: 364).isEmpty)
        #expect(issues(daysInclusive: 365) == [.raceTooFar])
        #expect(RaceSetupIssue.raceTooSoon.message == "Pick a race day at least 4 weeks from now.")
        #expect(RaceSetupIssue.raceTooFar.message == "Pick a race day within a year.")
    }

    @Test func distanceBoundaries() {
        #expect(issues(km: 0.9) == [.distanceOutOfRange])
        #expect(issues(km: 1).isEmpty)
        #expect(issues(km: 250).isEmpty)
        #expect(issues(km: 251) == [.distanceOutOfRange])
        #expect(RaceSetupIssue.distanceOutOfRange.message == "Enter a distance between 1 and 250 km.")
    }

    @Test func elevationBoundaries() {
        #expect(issues(gain: 10_000).isEmpty)
        #expect(issues(gain: 10_001) == [.elevationOutOfRange])
        #expect(issues(gain: -1) == [.elevationOutOfRange])
        #expect(RaceSetupIssue.elevationOutOfRange.message == "Enter 0 to 10,000 m or leave it blank.")
    }

    @Test func trainingDayBoundaries() {
        #expect(issues(days: [.monday]) == [.tooFewDays])
        #expect(issues(days: Set(Weekday.allCases)) == [.tooManyDays])
        #expect(issues(days: Set(Weekday.allCases.dropLast())).isEmpty)
        #expect(RaceSetupIssue.tooFewDays.message == "Choose at least 2 training days.")
        #expect(RaceSetupIssue.tooManyDays.message == "Keep at least one rest day.")
    }

    @Test func issuesComeInFieldOrder() {
        #expect(issues(daysInclusive: 10, km: 0, days: []).map(\.field) == [.raceDay, .distance, .trainingDays])
    }
}
