import Foundation
import Observation
import Domain
import Application

/// Drives the starting-point dashboard. Shows the cached summaries first, then
/// follows a background refresh section by section. Calls the use cases and
/// formats their results; every number and label comes from Domain.
@MainActor
@Observable
final class StartingPointViewModel {
    /// One percentile scale card, ready to draw.
    struct ScaleCard: Equatable {
        let value: String
        let unit: String
        let band: FitnessBand?
        /// Share of the population beaten, 0 to 100, when a scale is shown.
        let betterThan: Double?
        let statement: String?
        /// Muted text shown instead of the scale.
        let note: String?
        let measured: String?
        let source: String?
        let accessibilityLabel: String
    }

    /// A card, or a list, that has no data to draw.
    struct Message: Equatable {
        let text: String
        let showsSettingsHint: Bool
        let showsRetry: Bool
    }

    enum CardDisplay: Equatable {
        case loading
        case scale(ScaleCard)
        case message(Message)
    }

    enum RecordsDisplay: Equatable {
        case loading
        case rows([RecordRow])
        case message(Message)
    }

    enum PlansDisplay: Equatable {
        case loading
        case plans([PlanSuggestion])
        case message(Message)
    }

    enum RowDisplay: Equatable {
        case loading
        case value(String)
        case hidden
    }

    struct RecordRow: Equatable {
        let distance: RecordDistance
        let time: String?
        let detail: String?
        let isEstimated: Bool
        let isOlder: Bool
        let isNew: Bool
    }

    struct Subtitle: Equatable {
        let text: String
        let showsSpinner: Bool
    }

    let caption = "Your starting point"
    let title = "Here's where you are"
    static let settingsHint = "If you expected data here, check Settings > Health > Data Access & Devices."

    private(set) var profile: SectionState<ProfileSummary> = .loading
    private(set) var vo2Max: SectionState<VO2MaxSummary> = .loading
    private(set) var restingHeartRate: SectionState<RestingHeartRateSummary> = .loading
    private(set) var workouts: SectionState<WorkoutsSummary> = .loading
    private(set) var selectedPlan: PlanKind?
    /// The last full live read, for the DEBUG raw-data sheet. Never cached.
    private(set) var lastLiveRead: HealthSnapshot?

    private var vo2Baseline: MetricBaseline?
    private var restingBaseline: MetricBaseline?
    private var suggestions: [PlanSuggestion] = []
    private var hasLoaded = false
    private var lastRefreshStart: Date?
    private var refreshTask: Task<Void, Never>?

    private let loadCachedSnapshot: LoadCachedSnapshot
    private let refreshHealthSnapshot: RefreshHealthSnapshot
    private let computeFitnessBaseline: ComputeFitnessBaseline
    private let suggestPlans: SuggestPlans
    private let clock: any Clock
    private let calendar: Calendar
    private let onContinue: @MainActor (RaceSetupDraft) -> Void

    init(
        loadCachedSnapshot: LoadCachedSnapshot,
        refreshHealthSnapshot: RefreshHealthSnapshot,
        computeFitnessBaseline: ComputeFitnessBaseline,
        suggestPlans: SuggestPlans,
        clock: any Clock,
        calendar: Calendar,
        onContinue: @escaping @MainActor (RaceSetupDraft) -> Void
    ) {
        self.loadCachedSnapshot = loadCachedSnapshot
        self.refreshHealthSnapshot = refreshHealthSnapshot
        self.computeFitnessBaseline = computeFitnessBaseline
        self.suggestPlans = suggestPlans
        self.clock = clock
        self.calendar = calendar
        self.onContinue = onContinue
    }

    // MARK: Loading

    /// Draws the cache at once, then refreshes in the background.
    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        if let cached = await loadCachedSnapshot.execute() {
            profile = Self.fromCache(cached.profile)
            vo2Max = Self.fromCache(cached.vo2Max)
            restingHeartRate = Self.fromCache(cached.restingHeartRate)
            workouts = Self.fromCache(cached.workouts)
            await recompute()
        }
        await refresh()
    }

    /// Runs a refresh, or waits for the one already running.
    func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            for await update in self.refreshHealthSnapshot.execute() {
                await self.apply(update)
            }
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    /// On returning to the foreground: only when the last refresh is old enough.
    func refreshIfStale() async {
        guard refreshHealthSnapshot.isStale(lastRefreshStart: lastRefreshStart) else { return }
        await refresh()
    }

    private static func fromCache<Value>(_ section: CachedSection<Value>?) -> SectionState<Value> {
        section.map { .ready($0.value, asOf: $0.asOf, fromCache: true) } ?? .loading
    }

    private func apply(_ update: HealthRefreshUpdate) async {
        switch update {
        case .started(let date): lastRefreshStart = date
        case .profile(let state): profile = state
        case .vo2Max(let state): vo2Max = state
        case .restingHeartRate(let state): restingHeartRate = state
        case .workouts(let state): workouts = state
        case .finished(let snapshot): lastLiveRead = snapshot
        }
        await recompute()
    }

    /// Comparisons wait for the profile (age and sex pick the table). Plans follow
    /// the workouts. Only the first fill picks the Best fit default.
    private func recompute() async {
        if profile.isLoading {
            vo2Baseline = nil
            restingBaseline = nil
        } else {
            vo2Baseline = await computeFitnessBaseline.vo2Max(vo2Max.value, profile: profile.value)
            restingBaseline = await computeFitnessBaseline.restingHeartRate(restingHeartRate.value, profile: profile.value)
        }

        switch workouts {
        case .emptyOrNotAllowed:
            suggestions = suggestPlans.execute(.none)
        default:
            suggestions = workouts.value.map { suggestPlans.execute($0.volume) } ?? []
        }
        if selectedPlan == nil {
            selectedPlan = suggestions.first { $0.label == .bestFit }?.plan
        }
    }

    // MARK: Header

    var subtitle: Subtitle {
        if let summary = workouts.value, let asOf = workouts.asOf {
            let updated = UpdatedLabel.text(now: clock.now(), then: asOf, calendar: calendar)
            return Subtitle(text: "Based on \(summary.totalCount) workouts · updated \(updated)", showsSpinner: false)
        }
        switch workouts {
        case .loading: return Subtitle(text: "Reading your Apple Health data…", showsSpinner: true)
        case .emptyOrNotAllowed: return Subtitle(text: "No workouts found in Apple Health yet.", showsSpinner: false)
        default: return Subtitle(text: "Your workouts couldn't be read yet.", showsSpinner: false)
        }
    }

    /// Shown only while some section is locked.
    var lockedBannerText: String? {
        let lockedDates: [Date?] = [
            profile.isLocked ? profile.asOf : nil,
            vo2Max.isLocked ? vo2Max.asOf : nil,
            restingHeartRate.isLocked ? restingHeartRate.asOf : nil,
            workouts.isLocked ? workouts.asOf : nil,
        ]
        guard profile.isLocked || vo2Max.isLocked || restingHeartRate.isLocked || workouts.isLocked else { return nil }
        let start = "Health data can't be refreshed while it's locked."
        let end = "Unlock your phone, then pull down to refresh."
        guard let oldest = lockedDates.compactMap({ $0 }).min() else { return "\(start) \(end)" }
        return "\(start) Showing what we found at \(time(oldest)). \(end)"
    }

    // MARK: Cards

    var vo2MaxCard: CardDisplay {
        card(vo2Max, baseline: vo2Baseline, kind: .vo2Max)
    }

    var restingHeartRateCard: CardDisplay {
        card(restingHeartRate, baseline: restingBaseline, kind: .restingHeartRate)
    }

    var runHeartRate: RowDisplay {
        if workouts.isLoading { return .loading }
        guard let average = workouts.value?.runHeartRateAverage else { return .hidden }
        return .value("\(Int(average.rounded())) bpm")
    }

    private func card<Value>(_ state: SectionState<Value>, baseline: MetricBaseline?, kind: ScaleText.Kind) -> CardDisplay {
        switch state {
        case .loading:
            return .loading
        case .ready, .locked(cachedValue: .some, _):
            guard let baseline else { return .loading }
            return .scale(ScaleText.card(for: baseline, kind: kind))
        case .locked(cachedValue: .none, _):
            return .message(Message(text: "Unlock your phone to read this.", showsSettingsHint: false, showsRetry: false))
        case .emptyOrNotAllowed:
            return .message(Message(text: ScaleText.missingNote(kind), showsSettingsHint: true, showsRetry: false))
        case .failed:
            return .message(Message(text: "This couldn't be read from Apple Health.", showsSettingsHint: false, showsRetry: true))
        }
    }

    // MARK: Records

    var records: RecordsDisplay {
        switch workouts {
        case .loading:
            return .loading
        case .locked(cachedValue: .none, _):
            return .message(Message(text: "Unlock your phone to read this.", showsSettingsHint: false, showsRetry: false))
        case .failed:
            return .message(Message(text: "Your workouts couldn't be read from Apple Health.", showsSettingsHint: false, showsRetry: true))
        case .emptyOrNotAllowed:
            return .rows(RecordDistance.allCases.map(Self.emptyRow))
        case .ready(let summary, _, _), .locked(cachedValue: .some(let summary), _):
            return .rows(computeFitnessBaseline.records(summary).map(Self.row))
        }
    }

    private static func emptyRow(_ distance: RecordDistance) -> RecordRow {
        RecordRow(distance: distance, time: nil, detail: nil, isEstimated: false, isOlder: false, isNew: false)
    }

    private static func row(_ row: PersonalRecordRow) -> RecordRow {
        guard let display = row.record else { return emptyRow(row.distance) }
        let record = display.record
        var parts = [
            "\(duration(record.paceSecondsPerKm)) /km",
            record.date.formatted(.dateTime.day().month(.abbreviated).year()),
        ]
        if display.isEstimated {
            let kilometres = (record.actualDistanceMeters / 1_000).formatted(.number.precision(.fractionLength(2)))
            parts.append("from a \(kilometres) km run")
        }
        return RecordRow(
            distance: row.distance,
            time: duration(record.timeSeconds),
            detail: parts.joined(separator: " · "),
            isEstimated: display.isEstimated,
            isOlder: display.isOlder,
            isNew: display.isNew
        )
    }

    // MARK: Plans

    var plans: PlansDisplay {
        if workouts.isLoading { return .loading }
        if suggestions.isEmpty {
            return .message(Message(
                text: "Plans need your workouts. Pull down to try again.",
                showsSettingsHint: false,
                showsRetry: !workouts.isLocked
            ))
        }
        return .plans(suggestions)
    }

    var primaryTitle: String {
        if workouts.isLoading { return "Reading your data…" }
        guard let selectedPlan else { return "Continue" }
        return "Continue with the \(Self.title(selectedPlan))"
    }

    var isPrimaryEnabled: Bool {
        !workouts.isLoading && selectedPlan != nil && !suggestions.isEmpty
    }

    /// Custom race needs no data, so it is always available.
    let isCustomRaceEnabled = true

    func select(_ plan: PlanKind) {
        selectedPlan = plan
    }

    /// Race setup, prefilled with the selected plan's distance and race day.
    func continueWithSelectedPlan() {
        guard isPrimaryEnabled, let suggestion = suggestions.first(where: { $0.plan == selectedPlan }) else { return }
        onContinue(.suggested(suggestion, calendar: calendar))
    }

    /// Race setup with nothing filled in.
    func chooseCustomRace() {
        onContinue(.custom)
    }

    // MARK: Formatting

    /// "08:12" today, otherwise "3 Oct, 08:12".
    private func time(_ date: Date) -> String {
        calendar.isDate(date, inSameDayAs: clock.now())
            ? date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            : date.formatted(.dateTime.day().month(.abbreviated).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func title(_ plan: PlanKind) -> String {
        switch plan {
        case .fiveK: "5K plan"
        case .tenK: "10K plan"
        case .halfMarathon: "Half marathon plan"
        case .marathon: "Marathon plan"
        }
    }

    static func badge(_ plan: PlanKind) -> String {
        switch plan {
        case .fiveK: "5K"
        case .tenK: "10K"
        case .halfMarathon: "21K"
        case .marathon: "42K"
        }
    }

    static func label(_ fit: FitLabel) -> String {
        switch fit {
        case .bestFit: "Best fit"
        case .greatFit: "Great fit"
        case .stretch: "Stretch"
        case .later: "Later"
        }
    }

    static func schedule(_ suggestion: PlanSuggestion) -> String {
        "\(suggestion.weeks) weeks · \(suggestion.runsPerWeek) runs a week"
    }

    /// "Sun 6 Dec 2026".
    static func raceDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }

    /// "21:28" under an hour, "1:58:10" from an hour.
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3_600
        let minutes = total % 3_600 / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

/// The words around a percentile scale. Kept apart from the view model so the
/// wording rules are in one place and easy to test.
enum ScaleText {
    enum Kind {
        case vo2Max
        case restingHeartRate
    }

    static func card(for metric: MetricBaseline, kind: Kind) -> StartingPointViewModel.ScaleCard {
        guard let reading = metric.reading else {
            return StartingPointViewModel.ScaleCard(
                value: "–",
                unit: unit(kind),
                band: nil,
                betterThan: nil,
                statement: nil,
                note: missingNote(kind),
                measured: nil,
                source: nil,
                accessibilityLabel: "\(name(kind)): \(missingNote(kind))"
            )
        }

        let value = formatted(reading.value, kind: kind)
        let measured = "Measured \(reading.date.formatted(.dateTime.day().month(.abbreviated).year()))"

        switch metric.norm {
        case .compared(let comparison):
            let statement = statement(comparison, kind: kind)
            return StartingPointViewModel.ScaleCard(
                value: value,
                unit: unit(kind),
                band: comparison.result.band,
                betterThan: comparison.result.betterThanPercent,
                statement: statement,
                note: nil,
                measured: measured,
                source: comparison.source,
                accessibilityLabel: "\(name(kind)) \(value) \(unit(kind)), \(spoken(comparison, kind: kind))"
            )
        case .unavailable(let reason):
            return StartingPointViewModel.ScaleCard(
                value: value,
                unit: unit(kind),
                band: nil,
                betterThan: nil,
                statement: nil,
                note: note(reason),
                measured: measured,
                source: nil,
                accessibilityLabel: "\(name(kind)) \(value) \(unit(kind)). \(note(reason))"
            )
        case nil:
            return StartingPointViewModel.ScaleCard(
                value: value, unit: unit(kind), band: nil, betterThan: nil, statement: nil, note: nil,
                measured: measured, source: nil, accessibilityLabel: "\(name(kind)) \(value) \(unit(kind))"
            )
        }
    }

    /// Interior: "Better/Lower than about n% …". At an edge, "In the top/bottom n% …",
    /// where n comes from the nearest anchor.
    static func statement(_ comparison: NormComparison, kind: Kind) -> String {
        let group = population(comparison.population)
        let betterThan = comparison.result.betterThanPercent
        let heartRateNote = kind == .restingHeartRate ? " For heart rate, lower is better." : ""
        switch comparison.result.edge {
        case .top:
            return "In the top \(whole(100 - betterThan))% of \(group).\(heartRateNote)"
        case .bottom:
            return "In the bottom \(whole(betterThan))% of \(group).\(heartRateNote)"
        case .none:
            switch kind {
            case .vo2Max: return "Better than about \(whole(betterThan))% of \(group)."
            case .restingHeartRate: return "Lower than about \(whole(betterThan))% of \(group).\(heartRateNote)"
            }
        }
    }

    static func note(_ reason: NormUnavailableReason) -> String {
        switch reason {
        case .ageUnknown: "Add your date of birth in the Health app."
        case .belowMinimumAge(let age): "Norms start at age \(age)."
        case .aboveMaximumAge(let age): "Norms end at age \(age)."
        case .sexNotSet: "Norms need a biological sex set in Health."
        case .normsUnavailable: "Comparison data couldn't be loaded, so the scale is hidden."
        }
    }

    static func missingNote(_ kind: Kind) -> String {
        switch kind {
        case .vo2Max: "No VO2 max yet. Your Watch estimates it after outdoor runs."
        case .restingHeartRate: "No resting heart rate yet."
        }
    }

    static func bandName(_ band: FitnessBand) -> String {
        switch band {
        case .low: "Low"
        case .belowAverage: "Below average"
        case .average: "Average"
        case .aboveAverage: "Above average"
        case .excellent: "Excellent"
        }
    }

    static func footnote(_ kind: Kind) -> String {
        switch kind {
        case .vo2Max:
            "Apple's estimate, compared with measured treadmill data from the FRIEND registry. Approximate."
        case .restingHeartRate:
            "Compared with US survey data (NHANES), measured differently from your Watch. Approximate."
        }
    }

    static func caveats(_ kind: Kind) -> [String] {
        let shared = "Approximate: your value is placed between published percentiles."
        switch kind {
        case .vo2Max:
            return [
                shared,
                "The reference group is people who took a treadmill test for the FRIEND registry, not everyone.",
                "Apple's VO2 max is an estimate from your Watch, not a lab measurement.",
            ]
        case .restingHeartRate:
            return [
                shared,
                "The reference group is a US health survey population (NHANES), not everyone.",
                "NHANES pulse was a manual count taken seated, which is measured differently from your Watch.",
            ]
        }
    }

    /// The text inside the marker bubble: "You · 53.8".
    static func bubble(_ card: StartingPointViewModel.ScaleCard) -> String {
        "You · \(card.value)"
    }

    private static func spoken(_ comparison: NormComparison, kind: Kind) -> String {
        let group = population(comparison.population)
        let betterThan = comparison.result.betterThanPercent
        switch comparison.result.edge {
        case .top: return "in the top \(whole(100 - betterThan)) percent of \(group)"
        case .bottom: return "in the bottom \(whole(betterThan)) percent of \(group)"
        case .none: return "better than about \(whole(betterThan)) percent of \(group)"
        }
    }

    private static func population(_ population: NormPopulation) -> String {
        switch population {
        case .ageAndSex: "people your age and sex"
        case .allAdults: "all adults your age"
        }
    }

    private static func name(_ kind: Kind) -> String {
        switch kind {
        case .vo2Max: "VO2 max"
        case .restingHeartRate: "Resting heart rate"
        }
    }

    private static func unit(_ kind: Kind) -> String {
        switch kind {
        case .vo2Max: "ml/kg/min"
        case .restingHeartRate: "bpm"
        }
    }

    /// VO2 max with one decimal, heart rate whole.
    private static func formatted(_ value: Double, kind: Kind) -> String {
        switch kind {
        case .vo2Max: value.formatted(.number.precision(.fractionLength(1)))
        case .restingHeartRate: "\(Int(value.rounded()))"
        }
    }

    private static func whole(_ value: Double) -> Int {
        Int(value.rounded())
    }
}
