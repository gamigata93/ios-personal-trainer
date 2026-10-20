import Foundation
import Testing
import Domain
import Application
@testable import HybridAthlete

@MainActor
struct RaceSetupViewModelTests {
    private let calendar = Calendar.current

    /// A 10K suggestion whose race day is 10 weeks from the real today.
    private var suggestion: PlanSuggestion {
        let raceDay = LocalDate(Date(), calendar: calendar).adding(days: 70).date(in: calendar)
        return PlanSuggestion(plan: .tenK, label: .bestFit, reason: "", readiness: 1.2, weeks: 8, runsPerWeek: 3, suggestedRaceDate: raceDay)
    }

    private func viewModel(_ draft: RaceSetupDraft, onBuild: @escaping @MainActor (RaceSetup, PlanSource) -> Void = { _, _ in }) -> RaceSetupViewModel {
        CompositionRoot.previewRaceSetupViewModel(draft: draft, onBuild: onBuild)
    }

    // MARK: Distance range and shortcuts

    private struct NowClock: Clock {
        func now() -> Date { Date() }
    }

    private func localized(_ draft: RaceSetupDraft, locale: Locale = Locale(identifier: "en_US"), onBuild: @escaping @MainActor (RaceSetup, PlanSource) -> Void = { _, _ in }) -> RaceSetupViewModel {
        RaceSetupViewModel(
            draft: draft, validateRaceSetup: ValidateRaceSetup(clock: NowClock(), calendar: calendar), calendar: calendar, locale: locale,
            onBuild: onBuild, onBack: {}
        )
    }

    private func suggestion(_ plan: PlanKind) -> PlanSuggestion {
        PlanSuggestion(
            plan: plan, label: .bestFit, reason: "", readiness: 1.2, weeks: 8, runsPerWeek: 3,
            suggestedRaceDate: LocalDate(Date(), calendar: calendar).adding(days: 70).date(in: calendar)
        )
    }

    @Test func chipsFillTheFieldAndClearTheError() {
        let model = localized(.custom)
        #expect(model.distanceText.isEmpty && model.selectedShortcut == nil)
        #expect(model.distancePlaceholder == "10")
        model.distanceText = "4"
        model.markTouched(.distance)
        #expect(model.visibleProblem == "Pick a race distance from 5 km up to a full marathon (42.195 km).")
        #expect(model.visibleProblemField == .distance)
        model.choose(.half)
        #expect(model.distanceText == "21.1")
        #expect(model.selectedShortcut == .half)
        #expect(model.visibleProblem == nil)
    }

    @Test func typingSelectsTheMatchingChip() {
        let model = localized(.custom)
        model.distanceText = "21.1"
        #expect(model.selectedShortcut == .half)
        model.distanceText = "42,195"
        #expect(model.selectedShortcut == .marathon)
        model.distanceText = "15"
        #expect(model.selectedShortcut == nil)
        model.distanceText = ""
        model.markTouched(.distance)
        #expect(model.visibleProblem == "Enter a race distance.")
        model.distanceText = "abc"
        #expect(model.visibleProblem == "Enter a race distance.")
    }

    @Test(arguments: [(PlanKind.fiveK, "5", DistanceShortcut.fiveK), (.tenK, "10", .tenK), (.halfMarathon, "21.1", .half), (.marathon, "42.2", .marathon)])
    func suggestedPlansPrefillTheirChip(_ plan: PlanKind, _ text: String, _ chip: DistanceShortcut) {
        let model = localized(.suggested(suggestion(plan), calendar: calendar))
        #expect(model.distanceText == text)
        #expect(model.selectedShortcut == chip)
    }

    @Test func aCommaLocaleShowsAndReadsCommas() {
        let model = localized(.suggested(suggestion(.halfMarathon), calendar: calendar), locale: Locale(identifier: "bg_BG"))
        #expect(model.distanceText == "21,1")
        model.distanceText = "42.2"
        #expect(model.selectedShortcut == .marathon)
        model.choose(.marathon)
        #expect(model.distanceText == "42,2")
    }

    @Test func buildStaysUnavailableUntilTheDistanceIsInRange() {
        var built: RaceSetup?
        let model = localized(.suggested(suggestion(.tenK), calendar: calendar)) { setup, _ in built = setup }
        model.toggle(.tuesday)
        model.toggle(.sunday)
        #expect(model.canBuild)
        for text in ["4.99", "42.21", "50", ""] {
            model.distanceText = text
            #expect(!model.canBuild, "\(text)")
        }
        model.distanceText = "42,2"
        #expect(model.canBuild)
        model.build()
        #expect(built?.distanceKm == 42.2)
    }

    @Test func nothingIsSelectedAtFirst() {
        let model = viewModel(.suggested(suggestion, calendar: calendar))
        #expect(Weekday.allCases.allSatisfy { !model.isSelected($0) })
        #expect(model.dayCountText == "Choose at least 2")
        #expect(!model.canBuild)
        #expect(model.visibleProblem == nil) // nothing touched yet
    }

    @Test func suggestedDraftPrefillsDistanceAndDate() {
        let model = viewModel(.suggested(suggestion, calendar: calendar))
        #expect(model.distanceText == "10")
        #expect(model.hasRaceDay)
        #expect(model.prefilledFrom == "10K plan")
    }

    @Test func customDraftIsBlank() {
        let model = viewModel(.custom)
        #expect(model.distanceText.isEmpty)
        #expect(model.raceDayText == "Choose a date")
        #expect(model.prefilledFrom == nil)
    }

    @Test func buildStaysOffUntilValidAndThenBuilds() throws {
        var built: (RaceSetup, PlanSource)?
        let model = viewModel(.suggested(suggestion, calendar: calendar)) { built = ($0, $1) }

        model.build() // tapped while invalid: reveals the problem instead
        #expect(built == nil)
        #expect(model.visibleProblem == "Choose at least 2 training days.")

        model.toggle(.tuesday)
        model.toggle(.thursday)
        #expect(model.dayCountText == "2 days a week")
        #expect(model.canBuild)

        model.build()
        let (setup, source) = try #require(built)
        #expect(setup.distanceKm == 10)
        #expect(setup.trainingDays == [.tuesday, .thursday])
        #expect(setup.elevationGainM == 0)
        #expect(source == .suggested(.tenK))
    }

    @Test func problemsShowOnlyForTouchedFields() {
        let model = viewModel(.custom)
        model.toggle(.monday)
        // The race day is missing too, but only the days were touched.
        #expect(model.visibleProblem == "Choose at least 2 training days.")
        model.build()
        #expect(model.visibleProblem == "Choose a race day.")
    }

    @Test func acceptsACommaDecimal() {
        let model = viewModel(.suggested(suggestion, calendar: calendar))
        model.distanceText = "21,1"
        model.toggle(.tuesday)
        model.toggle(.sunday)
        #expect(model.canBuild)
        model.elevationText = "10001"
        model.markTouched(.elevation)
        #expect(model.visibleProblem == "Enter 0 to 10,000 m or leave it blank.")
    }

    @Test func softHintWhenFewerDaysThanThePlanRuns() {
        let model = viewModel(.suggested(suggestion, calendar: calendar))
        model.toggle(.tuesday)
        model.toggle(.sunday)
        #expect(model.runsHint == "The 10K plan works best with 3 days a week.")
        #expect(model.canBuild) // a hint, not a block
        model.toggle(.thursday)
        #expect(model.runsHint == nil)
    }
}
