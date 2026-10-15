import Foundation
import Testing
@testable import Domain

struct HomeFormatTests {
    @Test(arguments: [
        (4, "Good evening"), (5, "Good morning"), (11, "Good morning"),
        (12, "Good afternoon"), (17, "Good afternoon"), (18, "Good evening"),
    ])
    func greetingEdges(hour: Int, expected: String) {
        #expect(HomeFormat.greeting(hour: hour) == expected)
    }

    @Test func weekRangeWithinAMonth() {
        #expect(HomeFormat.weekRangeLabel(start: LocalDate(year: 2026, month: 10, day: 12), end: LocalDate(year: 2026, month: 10, day: 18)) == "12 - 18 Oct")
    }

    @Test func weekRangeAcrossMonths() {
        #expect(HomeFormat.weekRangeLabel(start: LocalDate(year: 2026, month: 10, day: 26), end: LocalDate(year: 2026, month: 11, day: 1)) == "26 Oct - 1 Nov")
    }

    @Test func weekRangeAcrossYears() {
        #expect(HomeFormat.weekRangeLabel(start: LocalDate(year: 2026, month: 12, day: 28), end: LocalDate(year: 2027, month: 1, day: 3)) == "28 Dec - 3 Jan")
    }

    @Test(arguments: [
        (5.0, "5K race"), (10.0, "10K race"), (21.1, "Half marathon race"), (42.2, "Marathon race"),
        (12.0, "12 km race"), (10.5, "10K race"), (10.6, "10.6 km race"), (42.0, "Marathon race"),
    ])
    func raceTitles(distance: Double, expected: String) {
        #expect(HomeFormat.raceTitle(distanceKm: distance) == expected)
    }

    @Test func estimatedTime() {
        #expect(HomeFormat.estimatedTime(minutes: 25) == "~25 min")
        #expect(HomeFormat.estimatedTime(minutes: nil) == nil)
    }

    @Test func dates() {
        let date = LocalDate(year: 2026, month: 10, day: 28)
        #expect(HomeFormat.longDate(date) == "Wednesday, 28 October")
        #expect(HomeFormat.shortDate(date) == "Wed 28 Oct")
        #expect(HomeFormat.spokenDate(date) == "Wednesday 28 October")
    }

    @Test func kilometres() {
        #expect(HomeFormat.km(6) == "6")
        #expect(HomeFormat.km(7.5) == "7.5")
        #expect(HomeFormat.km(4.25) == "4.3")
    }
}
