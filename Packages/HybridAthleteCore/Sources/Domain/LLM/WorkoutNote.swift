import Foundation

/// Everything one post-workout note may use: the reviewed run, where the plan
/// stands and the recovery around the run. Summaries only, never routes or samples.
public struct WorkoutNoteRequest: Sendable, Equatable {
    public let review: WorkoutReview
    /// The plan's generatedBy ("template-v1").
    public let planSource: String
    public let program: ProgramStatus
    public let recovery: RecoveryFacts

    public init(review: WorkoutReview, planSource: String, program: ProgramStatus, recovery: RecoveryFacts) {
        self.review = review
        self.planSource = planSource
        self.program = program
        self.recovery = recovery
    }

    public var findings: [Finding] { Findings.make(review) }
}

/// The facts text sent to a model, in three parts: the workout, the program
/// and recovery. The input hash covers the workout part only, so a later
/// refresh of the program or recovery never makes a note stale.
public struct WorkoutFacts: Sendable, Equatable {
    public let level: Int
    public let workout: [String]
    public let program: [String]
    public let recovery: [String]

    public var lines: [String] { workout + program + recovery }
    public var text: String { lines.joined(separator: "\n") }
    /// What the input hash is computed from.
    public var hashText: String { workout.joined(separator: "\n") }
}

/// Builds the facts at a compaction level. Level 0 is full; 1 groups splits in
/// pairs and shows only the lap count; 2 groups splits by 5 km and keeps one
/// recent session; 3 drops splits, laps and the recent sessions line.
public enum FactsBuilder {
    public static let levels = 0...3

    public static func build(_ request: WorkoutNoteRequest, level: Int = 0) -> WorkoutFacts {
        let review = request.review
        let session = review.session
        let program = request.program
        var workout = ["Session: \(session.name) (\(SessionFormat.sessionTypeName(session.type)))", "Plan source: \(request.planSource)"]
        if let week = program.weekIndex, let phase = program.phase {
            let days = program.daysToRace
            workout.append("Plan position: week \(week) of \(program.weeksTotal), \(phase.rawValue) phase, \(days) \(days == 1 ? "day" : "days") to race.")
        }
        workout.append("Planned: \(SessionFormat.distanceText(km: session.distanceKm))")
        workout.append("Planned effort: \(session.effort)")
        if !session.segments.isEmpty {
            workout.append("Planned blocks:")
            workout += session.segments.map { segment in
                "- \(segment.label): \(segment.detail)" + (segment.distanceKm.map { " (\(SessionFormat.distanceText(km: $0)))" } ?? "")
            }
        }
        workout.append("Findings:")
        workout += request.findings.enumerated().map { "F\($0.offset + 1). \($0.element.text)" }
        let splits = review.analysis.splits
        if level < 3, !splits.isEmpty {
            workout.append("Splits (moving time):")
            switch level {
            case 0: workout += splits.map(splitRow)
            case 1: workout += groups(splits, size: 2).map(groupRow)
            default: workout += groups(splits, size: 5).map(groupRow)
            }
        }
        let laps = review.analysis.laps
        if level < 3, !laps.isEmpty {
            if level == 0 {
                workout.append("Laps:")
                workout += laps.map(lapRow)
            } else {
                workout.append("Laps: \(laps.count) laps recorded.")
            }
        }
        return WorkoutFacts(
            level: level,
            workout: workout,
            program: programLines(program, recentCount: level >= 3 ? 0 : (level == 2 ? 1 : AnalysisRules.recentSessionsInFacts)),
            recovery: RecoveryFactLines.lines(request.recovery)
        )
    }

    // MARK: Splits

    /// "km 1 · 6:30 /km · HR 135 · +3/−2 m"; a partial last split reads "km 6 (0.4 km) · ...".
    static func splitRow(_ split: WorkoutAnalysis.Split) -> String {
        let label = split.isFull ? "km \(split.index)" : "km \(split.index) (\(WorkoutFormat.oneDecimal(split.distanceKm)) km)"
        return row(label: label, pace: split.paceSecPerKm, hr: split.avgHr, gain: split.gainM, loss: split.lossM)
    }

    private static func row(label: String, pace: Double, hr: Double?, gain: Double?, loss: Double?) -> String {
        var parts = [label, WorkoutFormat.pace(pace)]
        if let hr { parts.append("HR \(AnalysisMath.rounded(hr))") }
        if let gain, let loss { parts.append("+\(AnalysisMath.rounded(gain))/\u{2212}\(AnalysisMath.rounded(loss)) m") }
        return parts.joined(separator: " · ")
    }

    private static func groups(_ splits: [WorkoutAnalysis.Split], size: Int) -> [[WorkoutAnalysis.Split]] {
        stride(from: 0, to: splits.count, by: size).map { Array(splits[$0..<min($0 + size, splits.count)]) }
    }

    /// "km 1–2 · 5:51 /km · HR 147 · +7/−5 m": average pace, time-weighted heart
    /// rate, summed gain and loss.
    static func groupRow(_ group: [WorkoutAnalysis.Split]) -> String {
        guard let first = group.first, let last = group.last else { return "" }
        let km = group.map(\.distanceKm).reduce(0, +)
        let seconds = group.map(\.movingSeconds).reduce(0, +)
        var label = first.index == last.index ? "km \(first.index)" : "km \(first.index)–\(last.index)"
        if !last.isFull { label += " (\(WorkoutFormat.oneDecimal(km)) km)" }
        let withHr = group.filter { $0.avgHr != nil }
        let hrSeconds = withHr.map(\.movingSeconds).reduce(0, +)
        let hr = withHr.count == group.count && hrSeconds > 0
            ? withHr.map { ($0.avgHr ?? 0) * $0.movingSeconds }.reduce(0, +) / hrSeconds
            : nil
        let hasElevation = group.allSatisfy { $0.gainM != nil && $0.lossM != nil }
        return row(
            label: label,
            pace: km > 0 ? seconds / km : 0,
            hr: hr,
            gain: hasElevation ? group.compactMap(\.gainM).reduce(0, +) : nil,
            loss: hasElevation ? group.compactMap(\.lossM).reduce(0, +) : nil
        )
    }

    /// "lap 1 · 1.0 km · 6:30 /km · HR 135".
    static func lapRow(_ lap: WorkoutAnalysis.Lap) -> String {
        var parts = ["lap \(lap.index)", SessionFormat.distanceText(km: lap.distanceKm), WorkoutFormat.pace(lap.paceSecPerKm)]
        if let hr = lap.avgHr { parts.append("HR \(AnalysisMath.rounded(hr))") }
        return parts.joined(separator: " · ")
    }

    // MARK: Program

    static func programLines(_ program: ProgramStatus, recentCount: Int) -> [String] {
        var lines = ["Program:"]
        if let percent = program.adherencePercent {
            lines.append("Plan adherence \(percent)% (\(program.completedCount) of \(program.dueCount) sessions).")
        }
        if let week = program.weekIndex {
            lines.append(
                "This week: \(WorkoutFormat.oneDecimal(program.kmDoneThisWeek)) of \(WorkoutFormat.oneDecimal(program.kmPlannedThisWeek)) km done "
                    + "(week \(week) of \(program.weeksTotal))."
            )
        }
        let recent = program.recent.prefix(recentCount)
        if !recent.isEmpty {
            lines.append("Recent sessions: " + recent.map { session in
                "\(WorkoutFormat.day(session.date)) \(session.name) \(WorkoutFormat.oneDecimal(session.doneKm))/"
                    + "\(WorkoutFormat.oneDecimal(session.plannedKm)) km (\(session.verdict.lowercasedText))"
            }.joined(separator: " · "))
        }
        if let next = program.next {
            lines.append("Next: \(WorkoutFormat.day(next.date)) \(next.name) \(SessionFormat.distanceText(km: next.km)).")
        }
        return lines.count > 1 ? lines : []
    }
}

/// The note prompt: fixed instructions, then the facts.
public enum DetailedNotePromptBuilder {
    public static let instructions = """
        You are a running coach writing a post-workout note for one athlete. Use ONLY the facts. \
        Copy numbers, paces and km marks exactly as written; never invent or round them. Write four short parts: \
        how it went, versus the plan, the program, and one next step. Compare the actual blocks with the planned \
        blocks using the block findings. Plain text, second person, no emoji, no markdown, no medical advice. \
        If the facts say effort was not assessed or data is missing, say so. Mention at most one recovery fact. \
        Respect the limits: headline 60, how it went 320, versus the plan 320, the program 280, next step 200 characters.
        """

    public static func build(_ facts: WorkoutFacts, revisionNotes: [String] = []) -> Prompt {
        var text = "Write the post-workout note.\n\nFacts:\n" + facts.text
        if !revisionNotes.isEmpty {
            text += "\n\nFix these problems:\n" + revisionNotes.joined(separator: "\n")
        }
        return Prompt(instructions: instructions, facts: facts.lines, text: text)
    }

    /// The facts and instructions as estimated tokens: ceil(characters / 3).
    public static func estimatedTokens(_ facts: WorkoutFacts) -> Int {
        AnalysisRules.estimatedTokens(characters: build(facts).fullText.count)
    }

    /// The smallest compaction level whose prompt fits contextSize x 0.55 - 700;
    /// nil when even level 3 does not fit (then the rules write the note).
    public static func fittingFacts(
        _ request: WorkoutNoteRequest,
        contextSize: Int?,
        estimate: (WorkoutFacts) -> Int = estimatedTokens
    ) -> WorkoutFacts? {
        let budget = AnalysisRules.factsBudget(contextSize: contextSize ?? AnalysisRules.defaultBudgetTokens)
        return FactsBuilder.levels.lazy.map { FactsBuilder.build(request, level: $0) }.first { estimate($0) <= budget }
    }
}

/// Checks a model's note against the facts. ANY issue rejects the note.
public enum DetailedNoteGuard {
    public enum Issue: Sendable, Equatable {
        case tooLong(field: String, limit: Int)
        case unsupportedNumbers([String])
        case unsupportedPaces([String])
        case badKmReference([String])
        case badZone([Int])

        /// The revision note sent back to the model.
        public var message: String {
            switch self {
            case .tooLong(let field, let limit): "\(field) is longer than \(limit) characters."
            case .unsupportedNumbers(let numbers): "These numbers are not in the facts: \(numbers.joined(separator: ", "))."
            case .unsupportedPaces(let paces): "These paces or times are not in the facts: \(paces.joined(separator: ", "))."
            case .badKmReference(let marks): "These km references do not fit the run: \(marks.joined(separator: ", "))."
            case .badZone(let zones): "These zones are not in the facts: \(zones.map { "zone \($0)" }.joined(separator: ", "))."
            }
        }
    }

    /// A note number matches a fact number within this.
    public static let numberTolerance = 0.05

    public static func issues(_ note: CoachNote, facts: String, runDistanceKm: Double) -> [Issue] {
        var issues: [Issue] = []
        let limits: [(String, String, Int)] = [
            ("Headline", note.headline, CoachNote.headlineLimit),
            ("How it went", note.howItWent, CoachNote.howItWentLimit),
            ("Versus the plan", note.versusPlan, CoachNote.versusPlanLimit),
            ("The program", note.programStatus, CoachNote.programStatusLimit),
            ("Next step", note.nextStep, CoachNote.nextStepLimit),
        ]
        for (field, text, limit) in limits where text.count > limit {
            issues.append(.tooLong(field: field, limit: limit))
        }
        let text = note.parts.joined(separator: "\n")
        let numbers = unsupportedNumbers(in: text, facts: facts)
        if !numbers.isEmpty { issues.append(.unsupportedNumbers(numbers)) }
        let paces = unsupportedPaces(in: text, facts: facts)
        if !paces.isEmpty { issues.append(.unsupportedPaces(paces)) }
        let marks = badKmReferences(in: text, facts: facts, runDistanceKm: runDistanceKm)
        if !marks.isEmpty { issues.append(.badKmReference(marks)) }
        let zones = badZones(in: text, facts: facts)
        if !zones.isEmpty { issues.append(.badZone(zones)) }
        return issues
    }

    /// Digit groups with an optional decimal that are not within ±0.05 of a
    /// number in the facts, in order, without repeats.
    public static func unsupportedNumbers(in text: String, facts: String) -> [String] {
        let known = numbers(in: facts).compactMap(Double.init)
        var seen: Set<String> = []
        return numbers(in: text).filter { token in
            guard let value = Double(token) else { return false }
            let supported = known.contains { abs($0 - value) <= numberTolerance + 1e-9 }
            return !supported && seen.insert(token).inserted
        }
    }

    /// m:ss tokens (paces and times) that do not appear exactly in the facts.
    public static func unsupportedPaces(in text: String, facts: String) -> [String] {
        let known = Set(times(in: facts))
        var seen: Set<String> = []
        return times(in: text).filter { !known.contains($0) && seen.insert($0).inserted }
    }

    /// "km N" / "kilometre N" outside 1...ceil(distance) (0 only as the start of
    /// a range, "km 0–1"), and "X km" values larger than the run that the facts
    /// do not hold as a km value.
    public static func badKmReferences(in text: String, facts: String, runDistanceKm: Double) -> [String] {
        let maxMark = Int((runDistanceKm - 1e-9).rounded(.up))
        var bad: [String] = []
        for match in text.matches(of: /(?i)\b(?:km|kilometre|kilometer)\s+(\d+)(\s*[–-])?/) {
            guard let mark = Int(match.output.1) else { continue }
            let isRangeStart = match.output.2 != nil
            let lowest = isRangeStart ? 0 : 1
            if mark < lowest || mark > maxMark { bad.append(String(match.output.0).trimmingCharacters(in: .whitespaces)) }
        }
        let factKm = kmValues(in: facts)
        for value in kmValues(in: text) where value > runDistanceKm + numberTolerance {
            if !factKm.contains(where: { abs($0 - value) <= numberTolerance + 1e-9 }) {
                bad.append("\(HomeFormat.km(value)) km")
            }
        }
        var seen: Set<String> = []
        return bad.filter { seen.insert($0).inserted }
    }

    /// "zone N" (and "zones A–B", "ZN") in the note whose number is not a zone in the facts.
    public static func badZones(in text: String, facts: String) -> [Int] {
        let known = zones(in: facts)
        var seen: Set<Int> = []
        return zones(in: text).filter { !known.contains($0) && seen.insert($0).inserted }
    }

    static func numbers(in text: String) -> [String] {
        text.matches(of: /\d+(?:\.\d+)?/).map { String($0.output) }
    }

    static func times(in text: String) -> [String] {
        text.matches(of: /\b\d{1,2}:\d{2}(?::\d{2})?\b/).map { String($0.output) }
    }

    static func kmValues(in text: String) -> [Double] {
        text.matches(of: /(\d+(?:\.\d+)?)\s*km\b/).compactMap { Double($0.output.1) }
    }

    static func zones(in text: String) -> [Int] {
        var result: [Int] = []
        for match in text.matches(of: /(?i)\bzones?\s+(\d)(?:\s*[–-]\s*(\d))?|\bZ(\d)\b/) {
            if let low = match.output.1.flatMap({ Int($0) }) {
                if let high = match.output.2.flatMap({ Int($0) }), high >= low {
                    result += Array(low...high)
                } else {
                    result.append(low)
                }
            }
            if let short = match.output.3.flatMap({ Int($0) }) { result.append(short) }
        }
        return result
    }
}

/// The rule-based note: deterministic, from the same review and program as the
/// facts. It is the final fallback, so it exists for every completed run.
public enum TemplateDetailedNoteWriter {
    public static func write(_ request: WorkoutNoteRequest) -> CoachNote {
        let review = request.review
        let findings = request.findings
        return CoachNote(
            headline: headline(review.verdict),
            howItWent: howItWent(review),
            versusPlan: versusPlan(review, findings: findings),
            programStatus: programStatus(request.program),
            nextStep: nextStep(review, recovery: request.recovery)
        )
    }

    static func headline(_ verdict: WorkoutVerdict) -> String {
        switch verdict {
        case .onTrack: "Right on plan"
        case .watch: "Worth a closer look"
        case .offPlan: "Off plan"
        }
    }

    /// "You ran 5.0 km at 5:43 /km, and every block of the session landed in its
    /// target heart rate zone." plus a drift or fade sentence when present.
    static func howItWent(_ review: WorkoutReview) -> String {
        let done = SessionFormat.distanceText(km: review.doneKm)
        var text = review.distance.isOnPlan
            ? "You ran \(done)"
            : "You ran \(done) against \(SessionFormat.distanceText(km: review.session.distanceKm)) planned"
        if let pace = review.paceSecPerKm { text += " at \(WorkoutFormat.pace(pace))" }
        if review.allBlocksOnTarget {
            text += review.blocks.count > 1
                ? ", and every block of the session landed in its target heart rate zone."
                : ", and your heart rate stayed in its target zone."
        } else {
            text += "."
        }
        if let drift = review.drift, drift.band != .low {
            text += " Your heart rate drifted \(WorkoutFormat.signed(drift.percent))% from the first to the last third."
        }
        if let fade = review.fade {
            text += " You slowed by \(AnalysisMath.rounded(fade.slowerSecPerKm)) s/km over the last 2 km."
        }
        return text
    }

    /// The block findings joined; single-block sessions use the split style instead.
    static func versusPlan(_ review: WorkoutReview, findings: [Finding]) -> String {
        if review.blocks.count > 1 {
            return review.blocks.map(Findings.blockText).joined(separator: " ")
        }
        return findings.first { $0.id == .style }?.text ?? "No planned blocks to compare."
    }

    /// "Plan adherence is 86% (6 of 7 sessions). One of your last 3 sessions was cut short."
    static func programStatus(_ program: ProgramStatus) -> String {
        var sentences: [String] = []
        if let percent = program.adherencePercent {
            sentences.append("Plan adherence is \(percent)% (\(program.completedCount) of \(program.dueCount) sessions).")
        }
        let recent = program.recent
        if recent.count == 1 {
            sentences.append(recent[0].verdict == .offPlan ? "Your last session was cut short." : "Your last session was on track.")
        } else if !recent.isEmpty {
            sentences.append(
                recent.contains { $0.verdict == .offPlan }
                    ? "One of your last \(recent.count) sessions was cut short."
                    : "Your last \(recent.count) sessions were on track."
            )
        }
        return sentences.isEmpty ? "No sessions are due yet." : sentences.joined(separator: " ")
    }

    /// Shortfall, then extra distance, then hard effort, otherwise by type; plus
    /// the HRV rider when HRV is lower than the recent nights.
    static func nextStep(_ review: WorkoutReview, recovery: RecoveryFacts) -> String {
        var text: String
        if review.distance.isShort {
            text = "Don't make it up. Pick the plan up with the next session."
        } else if case .long = review.distance {
            text = "Keep the next day easy so the extra distance doesn't pile up."
        } else if review.assessment.isEffortHard {
            text = "Start slower next time and let your heart rate settle before pushing."
        } else {
            switch review.session.type {
            case .easy: text = "Keep the next easy run just as relaxed."
            case .long: text = "Refuel and keep tomorrow easy."
            case .tempo, .threshold, .intervals: text = "Recover well before the next hard session."
            }
        }
        if recovery.hrv?.isWorse == true {
            text += " HRV is lower than your recent nights, so keep tomorrow easy."
        }
        return text
    }
}

extension WorkoutNoteRequest {
    /// The Lab's fixed sample: a 5.0 km tempo (warm-up 1.0, tempo 3.0, cool-down
    /// 1.0) run at 6:30, 5:12, 5:08, 5:06 and 6:40 /km with heart rate 135, 158,
    /// 164, 166 and 142; profile 182/49; adherence 6 of 7; HRV 58 ms −6%.
    public static let sampleTempo: WorkoutNoteRequest = {
        let date = LocalDate(year: 2026, month: 10, day: 12)
        let session = PlannedSession(
            date: date, type: .tempo, name: "Tempo run", distanceKm: 5, estimatedMinutes: 30, effort: "Comfortably hard",
            segments: [
                Segment(label: "Warm-up", detail: "Easy jog", distanceKm: 1),
                Segment(label: "Tempo", detail: "3 km continuous, comfortably hard", distanceKm: 3),
                Segment(label: "Cool-down", detail: "Easy jog", distanceKm: 1),
            ],
            note: nil
        )
        let legs: [(pace: Double, hr: Double, max: Double, gain: Double, loss: Double)] = [
            (390, 135, 148, 3, 2), (312, 158, 165, 4, 3), (308, 164, 168, 2, 2), (306, 166, 170, 3, 2), (400, 142, 156, 1, 3),
        ]
        let moving = legs.map(\.pace).reduce(0, +)
        let profile = HeartRateProfile(maxHr: 182, restingHr: 49)
        var bins: [Int: Double] = [:]
        for leg in legs { bins[AnalysisMath.rounded(leg.hr / 2) * 2, default: 0] += leg.pace }
        let analysis = WorkoutAnalysis(
            runId: "sample", computedAt: Date(timeIntervalSince1970: 0),
            dataQuality: WorkoutAnalysis.DataQuality(hasHr: true, hasRoute: true, hasDistanceSeries: true, hasCadence: false, hasPower: false),
            totals: WorkoutAnalysis.Totals(distanceKm: 5, movingSeconds: moving, elapsedSeconds: moving, pauseCount: 0, pausedSeconds: 0),
            splits: legs.enumerated().map { index, leg in
                WorkoutAnalysis.Split(
                    index: index + 1, distanceKm: 1, movingSeconds: leg.pace, paceSecPerKm: leg.pace,
                    avgHr: leg.hr, maxHr: leg.max, gainM: leg.gain, lossM: leg.loss
                )
            },
            hrHistogram: bins.keys.sorted().map { WorkoutAnalysis.HRBin(centerBpm: $0, seconds: bins[$0] ?? 0) },
            avgHr: legs.map { $0.hr * $0.pace }.reduce(0, +) / moving,
            maxHr: 170, elevationGainM: 13, elevationLossM: 12, sourceLabel: "Apple Watch"
        )
        let day = { (d: Int) in LocalDate(year: 2026, month: 10, day: d) }
        return WorkoutNoteRequest(
            review: WorkoutReview(
                session: session, run: CompletedRun(id: "sample", localDate: date, distanceKm: 5, durationSeconds: moving),
                analysis: analysis, profile: profile
            ),
            planSource: "template-v1",
            program: ProgramStatus(
                completedCount: 6, dueCount: 7, weekIndex: 3, weeksTotal: 8, kmDoneThisWeek: 12.4, kmPlannedThisWeek: 22.5,
                recent: [
                    ProgramStatus.RecentSession(date: day(26), name: "Tempo run", plannedKm: 6, doneKm: 6.2, verdict: .onTrack),
                    ProgramStatus.RecentSession(date: day(23), name: "Long run", plannedKm: 10, doneKm: 7, verdict: .offPlan),
                    ProgramStatus.RecentSession(date: day(19), name: "Tempo run", plannedKm: 5.5, doneKm: 5.5, verdict: .onTrack),
                ],
                next: ProgramStatus.NextSession(date: day(30), name: "Long run", km: 10),
                phase: .base, daysToRace: 39
            ),
            recovery: RecoveryFacts(hrv: HRVFact(valueMs: 58, deltaPercent: -6))
        )
    }()
}
