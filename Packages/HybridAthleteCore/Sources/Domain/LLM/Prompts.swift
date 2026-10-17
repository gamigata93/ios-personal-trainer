import Foundation

/// What a model is given: standing instructions and the request text built
/// from fact lines.
public struct Prompt: Sendable, Equatable, Codable {
    public let instructions: String
    /// One fact per line, as sent.
    public let facts: [String]
    /// The whole request text.
    public let text: String

    public init(instructions: String, facts: [String], text: String) {
        self.instructions = instructions
        self.facts = facts
        self.text = text
    }

    /// Instructions and request, as the Lab shows them.
    public var fullText: String { "\(instructions)\n\n\(text)" }
}

/// The recovery lines of the facts: sleep, HRV and resting heart rate, each
/// left out when missing.
public enum RecoveryFactLines {
    public static func lines(_ recovery: RecoveryFacts) -> [String] {
        var lines: [String] = []
        if let sleep = recovery.sleep {
            lines.append("Sleep last night: \(SleepFormat.durationText(minutes: sleep.asleepMinutes))" + sleepComparison(sleep))
        }
        if let hrv = recovery.hrv {
            let comparison = hrv.deltaPercent.map { delta -> String in
                let metric = MetricComparison(delta: delta, band: RecoveryRules.hrvNeutralPercent, countUsed: hrv.nightsUsed)
                return " (\(RecoveryFormat.hrvDeltaText(metric)) \(RecoveryFormat.hrvCaption(valuesUsed: hrv.nightsUsed)))"
            } ?? ""
            lines.append("HRV: \(RecoveryFormat.hrvValueText(hrv.valueMs)) ms" + comparison)
        }
        if let resting = recovery.restingHr {
            let comparison = resting.deltaBpm.map { delta -> String in
                let metric = MetricComparison(delta: delta, band: RecoveryRules.restingHRNeutralBpm, countUsed: resting.daysUsed)
                return " (\(RecoveryFormat.restingHRDeltaText(metric)) \(RecoveryFormat.restingHRCaption(valuesUsed: resting.daysUsed)))"
            } ?? ""
            lines.append("Resting heart rate: \(RecoveryFormat.restingHRValueText(resting.bpm)) bpm" + comparison)
        }
        return lines
    }

    private static func sleepComparison(_ sleep: SleepFact) -> String {
        guard let delta = sleep.deltaPercent else { return "" }
        let comparison = SleepComparison(
            averageMinutes: 0, deltaPercent: delta, trend: MetricTrend.of(deltaPercent: delta), nightsUsed: sleep.nightsUsed
        )
        return " (\(SleepFormat.deltaText(comparison)) \(SleepFormat.comparisonCaption(nightsUsed: sleep.nightsUsed)))"
    }
}

private extension MetricComparison {
    /// Only what the delta texts read: the delta, its trend and the count.
    init(delta: Double, band: Double, countUsed: Int) {
        self.init(average: 0, delta: delta, trend: MetricTrend.of(delta: delta, band: band), outcome: .neutral, countUsed: countUsed)
    }
}

/// The plan draft prompt: the race, the athlete's numbers and the rules.
public enum PlanPromptBuilder {
    /// The prompt asks for less weekly growth than `PlanValidator` allows, for margin.
    public static let promptWeeklyGrowthPercent = 115
    public static let maxRevisionNotes = 8

    public static let instructions = """
        You are a running coach drafting the structure of a training plan.
        For each week give its index, its phase and its sessions. Each session has a weekday,
        a type and a distance in km. Use only the facts and rules given. Keep distances to one decimal.
        """

    public static func build(_ request: PlanRequest) -> Prompt {
        let facts = factLines(request)
        var text = facts.joined(separator: "\n")
        let notes = Array(request.revisionNotes.prefix(maxRevisionNotes))
        if !notes.isEmpty {
            text += "\n\nFix these problems from your last attempt:\n" + notes.joined(separator: "\n")
        }
        return Prompt(instructions: instructions, facts: facts, text: text)
    }

    public static func factLines(_ request: PlanRequest) -> [String] {
        let race = request.race
        let fitness = request.fitness
        var lines = [
            "Race: \(HomeFormat.km(race.distanceKm)) km on \(race.raceDate) (\(HomeFormat.shortWeekday(race.raceDate.weekday)))",
            "Plan starts: \(request.planStart) (\(HomeFormat.shortWeekday(request.planStart.weekday)))",
            "Weeks: \(request.weekCount)",
            "Training days: " + race.trainingDays.sorted().map(\.name).joined(separator: ", "),
            "Elevation gain: \(Int(race.elevationGainM.rounded())) m",
            "Current weekly distance: \(SessionFormat.distanceText(km: fitness.weeklyKm))",
            "Longest recent run: \(SessionFormat.distanceText(km: fitness.longestRunKm))",
        ]
        if let pace = fitness.avgPaceSecPerKm, pace > 0 {
            lines.append("Average pace: \(SessionFormat.paceText(secondsPerKm: Int(pace.rounded())))")
        }
        lines += [
            "Phases in order: base, build, peak, taper (the last week is taper)",
            "Session types: easy, tempo, threshold, intervals, long",
            "Never plan more than \(promptWeeklyGrowthPercent)% of the larger of the previous two weeks' distance",
            "Long run cap: \(HomeFormat.km(PlanValidator.longRunCapKm(request.planKind))) km",
            "Use only the training days listed",
            "No session on the race day or the day before",
        ]
        return lines
    }
}
