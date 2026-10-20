import Foundation
import Testing
import Domain

@Suite("App scope: 5 km to a full marathon")
struct AppScopeTests {
    private func decimal(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? -1 }

    @Test func rangeIsInclusiveAndExact() {
        for text in ["4.99", "42.21", "45", "50", "0", "-1"] {
            #expect(!AppScope.isInScope(decimal(text)), "\(text)")
        }
        for text in ["5.0", "5.01", "42.195", "42.2"] {
            #expect(AppScope.isInScope(decimal(text)), "\(text)")
        }
        // Doubles compare as the decimal they print as.
        #expect(AppScope.isInScope(42.2))
        #expect(!AppScope.isInScope(42.21))
        #expect(AppScope.minRaceKm == 5 && AppScope.maxRaceKm == decimal("42.2") && AppScope.marathonKm == decimal("42.195"))
    }

    @Test(arguments: ["en_US", "bg_BG"])
    func parserAcceptsEitherSeparator(_ identifier: String) {
        let locale = Locale(identifier: identifier)
        #expect(RaceDistanceParser.parse("42.2", locale: locale) == decimal("42.2"))
        #expect(RaceDistanceParser.parse("42,2", locale: locale) == decimal("42.2"))
        #expect(RaceDistanceParser.parse(" 10 ", locale: locale) == 10)
        #expect(RaceDistanceParser.parse("21,0975", locale: locale) == decimal("21.0975"))
        for bad in ["10,5,1", "1.234,5", "4 2", "", "  ", "abc", "10km", ",5", "10."] {
            #expect(RaceDistanceParser.parse(bad, locale: locale) == nil, "\(bad)")
        }
    }

    @Test func shortcuts() {
        #expect(DistanceShortcut.selected(for: decimal("21.0975")) == .half)
        #expect(DistanceShortcut.selected(for: decimal("21.1")) == .half)
        #expect(DistanceShortcut.selected(for: decimal("42.195")) == .marathon)
        #expect(DistanceShortcut.selected(for: 15) == nil)
        #expect(DistanceShortcut.selected(for: 5) == .fiveK)
        #expect(DistanceShortcut.selected(for: decimal("10.04")) == .tenK)
        #expect(DistanceShortcut.selected(for: decimal("10.06")) == nil)
        #expect(DistanceShortcut.selected(for: nil) == nil)
        #expect(DistanceShortcut.allCases.map(\.value) == [5, 10, decimal("21.1"), decimal("42.2")])
        #expect(DistanceShortcut.half.accessibilityLabel == "Set distance to 21.1 kilometres, half marathon")
        #expect(DistanceShortcut.shortcut(for: .marathon) == .marathon)
    }

    @Test func distanceText() {
        #expect(DistanceText.km(15.0) == "15")
        #expect(DistanceText.km(21.1) == "21.1")
        #expect(DistanceText.km(42.195) == "42.195")
        #expect(DistanceText.km(42.2) == "42.2")
        #expect(DistanceText.km(10.0) == "10")
        #expect(DistanceText.km(decimal("21.09751")) == "21.098")
        // The race title is unchanged (one decimal).
        #expect(HomeFormat.raceTitle(distanceKm: 42.195) == "Marathon race")
        #expect(HomeFormat.raceTitle(distanceKm: 100) == "100 km race")
    }

    @Test func planKindEdgesAreUnchanged() {
        #expect(PlanKind.from(distanceKm: 6.0) == .fiveK)
        #expect(PlanKind.from(distanceKm: 6.01) == .tenK)
        #expect(PlanKind.from(distanceKm: 12.0) == .tenK)
        #expect(PlanKind.from(distanceKm: 12.01) == .halfMarathon)
        #expect(PlanKind.from(distanceKm: 25.0) == .halfMarathon)
        #expect(PlanKind.from(distanceKm: 25.01) == .marathon)
        #expect(PlanKind.from(distanceKm: 42.2) == .marathon)
    }
}
