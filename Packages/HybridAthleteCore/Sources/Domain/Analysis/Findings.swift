import Foundation

/// Everything code concludes about one completed run, ready to word: the
/// distance check, blocks, drift, style, fade, zones and the assessment. Pure.
public struct WorkoutReview: Sendable, Equatable {
    public let session: PlannedSession
    public let run: CompletedRun
    public let analysis: WorkoutAnalysis
    public let profile: HeartRateProfile?
    public let distance: DistanceCheck
    public let blocks: [AlignedBlock]
    public let drift: HeartRateDrift?
    public let style: SplitStyle?
    public let fade: Fade?
    /// Seconds per zone (index 0 = zone 1); nil without a profile or heart rate.
    public let zoneSeconds: [Double]?
    public let assessment: WorkoutAssessment

    public init(session: PlannedSession, run: CompletedRun, analysis: WorkoutAnalysis, profile: HeartRateProfile?) {
        self.session = session
        self.run = run
        self.analysis = analysis
        self.profile = profile
        let done = analysis.totals.distanceKm > 0 ? analysis.totals.distanceKm : run.distanceKm
        distance = DistanceCheck.check(plannedKm: session.distanceKm, doneKm: done)
        blocks = PlanAlignment.align(session: session, analysis: analysis, profile: profile)
        drift = HeartRateDrift.measure(analysis, type: session.type)
        style = SplitStyle.measure(analysis, type: session.type)
        fade = Fade.measure(analysis, type: session.type)
        zoneSeconds = profile.flatMap { profile in
            analysis.hrHistogram.isEmpty ? nil : ZoneTime.seconds(analysis, profile: profile)
        }
        assessment = WorkoutAssessment(distance: distance, blocks: blocks.map(\.check), drift: drift?.band)
    }

    /// The analysis distance, or the run's when the detail had none.
    public var doneKm: Double {
        analysis.totals.distanceKm > 0 ? analysis.totals.distanceKm : run.distanceKm
    }

    public var paceSecPerKm: Double? {
        analysis.totals.paceSecPerKm ?? (run.distanceKm > 0 ? run.durationSeconds / run.distanceKm : nil)
    }

    /// The workout's own summary heart rate stands in only when no detail could
    /// be read at all; a detail without heart rate means there is none.
    public var avgHr: Double? { analysis.avgHr ?? (isTotalsOnly ? run.avgHr : nil) }
    public var maxHr: Double? { analysis.maxHr ?? (isTotalsOnly ? run.maxHr : nil) }

    private var isTotalsOnly: Bool { analysis.splits.isEmpty && analysis.dataQuality == .none }

    /// The zone of the run's average heart rate.
    public var avgZone: Int? {
        guard let hr = avgHr, let profile else { return nil }
        return profile.zone(for: hr)
    }

    public var verdict: WorkoutVerdict { assessment.verdict }

    /// Every assessed block landed on target (and at least one was assessed).
    public var allBlocksOnTarget: Bool {
        let assessed = blocks.filter { $0.check != .notAssessed }
        return !assessed.isEmpty && assessed.allSatisfy { $0.check == .onTarget }
    }
}

/// One deterministic sentence that carries numbers the model may use.
public struct Finding: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Equatable, Codable {
        case distance, pace, pauses, style, fade, hr, drift, zones, block, elevation, cadence, power, weather, effort
    }

    public let id: Kind
    public let text: String

    public init(id: Kind, text: String) {
        self.id = id
        self.text = text
    }
}

/// The findings in order; one is left out when its data is missing.
public enum Findings {
    public static func make(_ review: WorkoutReview) -> [Finding] {
        let analysis = review.analysis
        var findings: [Finding] = [Finding(id: .distance, text: distanceText(review))]
        if let pace = review.paceSecPerKm {
            var text = "Average pace \(WorkoutFormat.pace(pace)) over \(SessionFormat.runDurationText(seconds: movingSeconds(review))) moving time"
            if analysis.totals.pauseCount > 0 {
                text += " (\(SessionFormat.runDurationText(seconds: analysis.totals.elapsedSeconds)) elapsed)"
            }
            findings.append(Finding(id: .pace, text: text + "."))
        }
        if analysis.totals.pauseCount > 0 {
            let count = analysis.totals.pauseCount
            findings.append(Finding(
                id: .pauses,
                text: "Paused \(count) \(count == 1 ? "time" : "times") for \(SessionFormat.runDurationText(seconds: analysis.totals.pausedSeconds))."
            ))
        }
        if let style = review.style {
            findings.append(Finding(
                id: .style,
                text: "Pace was \(style.kind.rawValue): first half \(WorkoutFormat.pace(style.firstHalfPace)), "
                    + "second half \(WorkoutFormat.pace(style.secondHalfPace)) (\(WorkoutFormat.signed(style.deltaSecPerKm)) s/km)."
            ))
        }
        if let fade = review.fade {
            findings.append(Finding(id: .fade, text: "Pace slowed by \(AnalysisMath.rounded(fade.slowerSecPerKm)) s/km over the last 2 km."))
        }
        if let avg = review.avgHr {
            let zone = review.avgZone.map { " (zone \($0))" } ?? ""
            let max = review.maxHr.map { ", max \(AnalysisMath.rounded($0)) bpm" } ?? ""
            findings.append(Finding(id: .hr, text: "Average heart rate \(AnalysisMath.rounded(avg)) bpm\(zone)\(max)."))
        }
        if let drift = review.drift {
            findings.append(Finding(
                id: .drift,
                text: "Heart rate drift \(WorkoutFormat.signed(drift.percent))% (\(drift.band.rawValue)) from the first to the last third."
            ))
        }
        if let zones = review.zoneSeconds {
            let parts = zones.enumerated()
                .filter { $0.element >= AnalysisRules.minZoneSeconds }
                .map { "Z\($0.offset + 1) \(AnalysisMath.rounded($0.element / 60)) min" }
            if !parts.isEmpty {
                findings.append(Finding(id: .zones, text: "Time in heart rate zones: " + parts.joined(separator: ", ") + "."))
            }
        }
        findings += review.blocks.map { Finding(id: .block, text: blockText($0)) }
        if let gain = analysis.elevationGainM {
            let text = analysis.elevationLossM.map { "Climbed \(AnalysisMath.rounded(gain)) m and descended \(AnalysisMath.rounded($0)) m." }
                ?? "Climbed \(AnalysisMath.rounded(gain)) m."
            findings.append(Finding(id: .elevation, text: text))
        }
        if let cadence = analysis.cadenceAvg {
            findings.append(Finding(id: .cadence, text: "Average cadence \(AnalysisMath.rounded(cadence)) steps per minute."))
        }
        if let power = analysis.powerAvg {
            findings.append(Finding(id: .power, text: "Average running power \(AnalysisMath.rounded(power)) W."))
        }
        if let weather = analysis.weather, let temperature = weather.temperatureCelsius {
            let humidity = weather.humidityPercent.map { ", humidity \(AnalysisMath.rounded($0))%" } ?? ""
            findings.append(Finding(id: .weather, text: "Weather: \(AnalysisMath.rounded(temperature)) °C\(humidity)."))
        }
        if let score = analysis.effortScore {
            findings.append(Finding(id: .effort, text: "Apple effort score \(AnalysisMath.rounded(score)) of 10."))
        }
        return findings
    }

    private static func movingSeconds(_ review: WorkoutReview) -> Double {
        review.analysis.totals.movingSeconds > 0 ? review.analysis.totals.movingSeconds : review.run.durationSeconds
    }

    /// "Distance matched the plan: 5.0 km of 5.0 km planned (As planned)." or
    /// "Distance was short: 7.0 km against 10.0 km planned (−3.0 km, 30%)."
    static func distanceText(_ review: WorkoutReview) -> String {
        let done = SessionFormat.distanceText(km: review.doneKm)
        let planned = SessionFormat.distanceText(km: review.session.distanceKm)
        let delta = SessionFormat.deltaKmText(review.distance.deltaKm)
        switch review.distance {
        case .onPlan:
            return "Distance matched the plan: \(done) of \(planned) planned (\(delta))."
        case .short(_, let percent):
            return "Distance was short: \(done) against \(planned) planned (\(delta), \(percent)%)."
        case .long(_, let percent):
            return "Distance was long: \(done) against \(planned) planned (\(delta), \(percent)%)."
        }
    }

    /// "Tempo (km 1–4): 5:09 /km, HR 163 bpm (zone 4); target zones 3–4: on target."
    public static func blockText(_ block: AlignedBlock) -> String {
        let head = "\(block.label) (km \(WorkoutFormat.kmMark(block.actualStartKm))–\(WorkoutFormat.kmMark(block.actualEndKm)))"
        if block.target == .mixed { return "\(head): reps and recoveries mixed, effort not assessed." }
        var measures: [String] = []
        if let pace = block.paceSecPerKm { measures.append(WorkoutFormat.pace(pace)) }
        if let hr = block.avgHr {
            measures.append("HR \(AnalysisMath.rounded(hr)) bpm" + (block.zone.map { " (zone \($0))" } ?? ""))
        }
        let body = measures.isEmpty ? head : "\(head): " + measures.joined(separator: ", ")
        switch block.target {
        case .zones(let low, let high, let upperOnly):
            let target = upperOnly ? "target up to zone \(high)" : "target zones \(low)–\(high)"
            return "\(body); \(target): \(block.check.text)."
        case .mixed, nil:
            return "\(body); effort not assessed."
        }
    }
}

/// Number formats shared by findings, facts and notes. Pure.
public enum WorkoutFormat {
    /// 343.2 -> "5:43 /km" (whole seconds, half up).
    public static func pace(_ secondsPerKm: Double) -> String {
        SessionFormat.paceText(secondsPerKm: AnalysisMath.rounded(secondsPerKm))
    }

    /// 0.96 -> "1", 3.84 -> "3.8", 4 -> "4": one decimal only when not whole.
    public static func kmMark(_ km: Double) -> String {
        let tenths = AnalysisMath.rounded(km * 10)
        return tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10).\(abs(tenths % 10))"
    }

    /// Whole number with its sign: "+9", "−9" (U+2212), "0".
    public static func signed(_ value: Double) -> String {
        let whole = AnalysisMath.rounded(value)
        if whole > 0 { return "+\(whole)" }
        if whole < 0 { return "\u{2212}\(-whole)" }
        return "0"
    }

    /// "Mon 26 Oct".
    public static func day(_ date: LocalDate) -> String {
        HomeFormat.shortDate(date)
    }

    /// One decimal: "12.4".
    public static func oneDecimal(_ value: Double) -> String {
        SessionFormat.oneDecimal(value)
    }

    /// Whole number, half away from zero: 151.55 -> 152.
    public static func rounded(_ value: Double) -> Int {
        AnalysisMath.rounded(value)
    }

    /// "152".
    public static func whole(_ value: Double) -> String {
        "\(AnalysisMath.rounded(value))"
    }
}
