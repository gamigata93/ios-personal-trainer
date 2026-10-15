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
