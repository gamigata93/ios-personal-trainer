import Foundation
import Observation
import Domain
import Application

/// Drives the race setup form: fields, which ones were touched, and the issue to
/// show. The rules themselves come from `RaceSetupValidator`.
@MainActor
@Observable
final class RaceSetupViewModel {
    /// A problem with the form, tied to the field it belongs to.
    struct Problem: Equatable {
        let message: String
        let field: RaceSetupField
    }

    static let missingRaceDay = Problem(message: "Choose a race day.", field: .raceDay)

    let draft: RaceSetupDraft
    let title = "Set up your race"
    let subtitle = "Your coach builds the whole plan around these details."

    private(set) var raceDate: LocalDate?
    var distanceText: String
    var elevationText = ""
    private(set) var trainingDays: Set<Weekday> = []
    private(set) var touched: Set<RaceSetupField> = []
    private(set) var showsAllProblems = false

    private let validateRaceSetup: ValidateRaceSetup
    private let calendar: Calendar
    private let onBuild: @MainActor (RaceSetup, PlanSource) -> Void
    private let onBack: @MainActor () -> Void

    init(
        draft: RaceSetupDraft,
        validateRaceSetup: ValidateRaceSetup,
        calendar: Calendar,
        onBuild: @escaping @MainActor (RaceSetup, PlanSource) -> Void,
        onBack: @escaping @MainActor () -> Void
    ) {
        self.draft = draft
        self.validateRaceSetup = validateRaceSetup
        self.calendar = calendar
        self.onBuild = onBuild
        self.onBack = onBack
        self.raceDate = draft.raceDate
        self.distanceText = draft.distanceKm.map(Self.distanceText) ?? ""
    }

    // MARK: Header

    /// "10K plan" when the race came from a suggested plan.
    var prefilledFrom: String? {
        guard case .suggested(let suggestion) = draft.source else { return nil }
        return StartingPointViewModel.title(suggestion.plan)
    }

    var distancePlaceholder: String { "42" }

    // MARK: Race day

    var raceDayText: String {
        guard let raceDate, let date = raceDate.date(in: calendar) else { return "Choose a date" }
        return StartingPointViewModel.raceDay(date)
    }

    var hasRaceDay: Bool { raceDate != nil }

    /// Where the picker opens: the chosen day, or the first Sunday 12 weeks out.
    var pickerDate: Date {
        let twelveWeeks = validateRaceSetup.today.adding(days: 12 * 7)
        let sunday = twelveWeeks.adding(days: (Weekday.sunday.index - twelveWeeks.weekday.index + 7) % 7)
        return (raceDate ?? sunday).date(in: calendar) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    /// Tomorrow to a little over a year out; the validator explains anything outside 4 to 52 weeks.
    var pickerRange: ClosedRange<Date> {
        let today = validateRaceSetup.today
        let lower = today.adding(days: 1).date(in: calendar) ?? .distantPast
        let upper = today.adding(days: 400).date(in: calendar) ?? .distantFuture
        return lower...upper
    }

    func setRaceDay(_ date: Date) {
        raceDate = LocalDate(date, calendar: calendar)
        touched.insert(.raceDay)
    }

    // MARK: Days

    func isSelected(_ day: Weekday) -> Bool {
        trainingDays.contains(day)
    }

    func toggle(_ day: Weekday) {
        if trainingDays.contains(day) {
            trainingDays.remove(day)
        } else {
            trainingDays.insert(day)
        }
        touched.insert(.trainingDays)
    }

    /// "Choose at least 2" until two days are chosen, then "{n} days a week".
    var dayCountText: String {
        trainingDays.count < RaceSetupValidator.trainingDayRange.lowerBound
            ? "Choose at least 2"
            : "\(trainingDays.count) days a week"
    }

    var hasEnoughDays: Bool {
        trainingDays.count >= RaceSetupValidator.trainingDayRange.lowerBound
    }

    /// A gentle note, never a block: fewer days than the suggested plan was sized for.
    var runsHint: String? {
        guard
            let runs = draft.runsPerWeek,
            let plan = prefilledFrom,
            hasEnoughDays,
            trainingDays.count < runs
        else { return nil }
        return "The \(plan) works best with \(runs) days a week."
    }

    // MARK: Validation

    func markTouched(_ field: RaceSetupField) {
        touched.insert(field)
    }

    var problems: [Problem] {
        guard let setup else { return [Self.missingRaceDay] + validatedProblems(raceDate: validateRaceSetup.today.adding(days: 12 * 7)) }
        return validateRaceSetup.execute(setup).map { Problem(message: $0.message, field: $0.field) }
    }

    /// The first problem, once its field was touched or Build was tapped.
    var visibleProblem: String? {
        problems.first { showsAllProblems || touched.contains($0.field) }?.message
    }

    var canBuild: Bool { problems.isEmpty }

    /// Tapping while invalid reveals the first problem instead of building.
    func build() {
        guard canBuild, let setup else {
            showsAllProblems = true
            return
        }
        onBuild(setup, draft.planSource)
    }

    func back() {
        onBack()
    }

    // MARK: Parsing

    private var setup: RaceSetup? {
        guard let raceDate else { return nil }
        return RaceSetup(distanceKm: distanceKm, elevationGainM: elevationGainM, raceDate: raceDate, trainingDays: trainingDays)
    }

    /// The field problems without a race day, checked against a placeholder date
    /// so the other fields still report while the date is missing.
    private func validatedProblems(raceDate: LocalDate) -> [Problem] {
        let placeholder = RaceSetup(distanceKm: distanceKm, elevationGainM: elevationGainM, raceDate: raceDate, trainingDays: trainingDays)
        return validateRaceSetup.execute(placeholder)
            .filter { $0.field != .raceDay }
            .map { Problem(message: $0.message, field: $0.field) }
    }

    /// Accepts "21.1" and "21,1". Blank or unreadable is 0, which the validator rejects.
    private var distanceKm: Double {
        Self.number(distanceText) ?? 0
    }

    /// Blank is 0; unreadable is -1, which the validator rejects.
    private var elevationGainM: Double {
        let trimmed = elevationText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return 0 }
        return Self.number(trimmed) ?? -1
    }

    private static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private static func distanceText(_ km: Double) -> String {
        km.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }
}
