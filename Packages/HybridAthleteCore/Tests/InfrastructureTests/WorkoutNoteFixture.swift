import Foundation
import Domain

/// The worked workout-note scenarios, hand-calculated. Profile: max 182,
/// resting 49 (boundaries 115.5, 128.8, 142.1, 155.4, 168.7).
enum WorkoutNoteFixture {
    static let profile = HeartRateProfile(maxHr: 182, restingHr: 49)

    static func day(_ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: 2026, month: month, day: day)
    }

    // MARK: Scenario A: tempo 5.0 km on Mon 12 Oct 2026

    static let tempoSession = PlannedSession(
        date: day(10, 12),
        type: .tempo,
        name: "Tempo run",
        distanceKm: 5.0,
        estimatedMinutes: 30,
        effort: "Comfortably hard",
        segments: [
            Segment(label: "Warm-up", detail: "Easy jog", distanceKm: 1.0),
            Segment(label: "Tempo", detail: "3 km continuous, comfortably hard", distanceKm: 3.0),
            Segment(label: "Cool-down", detail: "Easy jog", distanceKm: 1.0),
        ],
        note: nil
    )

    static let tempoRun = CompletedRun(id: "run-a", localDate: day(10, 12), distanceKm: 5.0, durationSeconds: 1_716)

    /// (pace, avg HR, max HR, gain, loss) per km.
    static let tempoSplits: [(Double, Double, Double, Double, Double)] = [
        (390, 135, 148, 3, 2), (312, 158, 165, 4, 3), (308, 164, 168, 2, 2), (306, 166, 170, 3, 2), (400, 142, 156, 1, 3),
    ]

    static func analysis(
        splits: [(Double, Double, Double, Double, Double)], hasHr: Bool = true, hasElevation: Bool = true,
        pauses: (count: Int, seconds: Double) = (0, 0), runId: String = "run-a"
    ) -> WorkoutAnalysis {
        let moving = splits.map(\.0).reduce(0, +)
        let hrSum = splits.map { $0.0 * $0.1 }.reduce(0, +)
        var bins: [Int: Double] = [:]
        for split in splits {
            let center = Int((split.1 / 2).rounded(.toNearestOrAwayFromZero)) * 2
            bins[center, default: 0] += split.0
        }
        return WorkoutAnalysis(
            runId: runId,
            computedAt: Date(timeIntervalSince1970: 0),
            dataQuality: WorkoutAnalysis.DataQuality(hasHr: hasHr, hasRoute: hasElevation, hasDistanceSeries: true, hasCadence: false, hasPower: false),
            totals: WorkoutAnalysis.Totals(
                distanceKm: Double(splits.count), movingSeconds: moving, elapsedSeconds: moving + pauses.seconds,
                pauseCount: pauses.count, pausedSeconds: pauses.seconds
            ),
            splits: splits.enumerated().map { index, split in
                WorkoutAnalysis.Split(
                    index: index + 1, distanceKm: 1, movingSeconds: split.0, paceSecPerKm: split.0,
                    avgHr: hasHr ? split.1 : nil, maxHr: hasHr ? split.2 : nil,
                    gainM: hasElevation ? split.3 : nil, lossM: hasElevation ? split.4 : nil
                )
            },
            hrHistogram: hasHr ? bins.keys.sorted().map { WorkoutAnalysis.HRBin(centerBpm: $0, seconds: bins[$0] ?? 0) } : [],
            avgHr: hasHr ? hrSum / moving : nil,
            maxHr: hasHr ? splits.map(\.2).max() : nil,
            elevationGainM: hasElevation ? splits.map(\.3).reduce(0, +) : nil,
            elevationLossM: hasElevation ? splits.map(\.4).reduce(0, +) : nil,
            sourceLabel: "Apple Watch"
        )
    }

    static let tempoAnalysis = analysis(splits: tempoSplits)

    /// Today Wed 28 Oct 2026: adherence 6 of 7, week 3 of 8 (12.4 of 22.5 km),
    /// next Fri 30 Oct long run 10.0 km.
    static let program = ProgramStatus(
        completedCount: 6, dueCount: 7, weekIndex: 3, weeksTotal: 8, kmDoneThisWeek: 12.4, kmPlannedThisWeek: 22.5,
        recent: [
            ProgramStatus.RecentSession(date: day(10, 26), name: "Tempo run", plannedKm: 6.0, doneKm: 6.2, verdict: .onTrack),
            ProgramStatus.RecentSession(date: day(10, 23), name: "Long run", plannedKm: 10.0, doneKm: 7.0, verdict: .offPlan),
            ProgramStatus.RecentSession(date: day(10, 19), name: "Tempo run", plannedKm: 5.5, doneKm: 5.5, verdict: .onTrack),
        ],
        next: ProgramStatus.NextSession(date: day(10, 30), name: "Long run", km: 10.0),
        phase: .base,
        daysToRace: 39
    )

    static let hrvWorse = RecoveryFacts(hrv: HRVFact(valueMs: 58, deltaPercent: -6))

    static func request(
        session: PlannedSession = tempoSession,
        run: CompletedRun = tempoRun,
        analysis: WorkoutAnalysis = tempoAnalysis,
        profile: HeartRateProfile? = profile,
        recovery: RecoveryFacts = hrvWorse
    ) -> WorkoutNoteRequest {
        WorkoutNoteRequest(
            review: WorkoutReview(session: session, run: run, analysis: analysis, profile: profile),
            planSource: "template-v1",
            program: program,
            recovery: recovery
        )
    }

    static let requestA = request()

    static let factsA = """
        Session: Tempo run (Tempo)
        Plan source: template-v1
        Plan position: week 3 of 8, base phase, 39 days to race.
        Planned: 5.0 km
        Planned effort: Comfortably hard
        Planned blocks:
        - Warm-up: Easy jog (1.0 km)
        - Tempo: 3 km continuous, comfortably hard (3.0 km)
        - Cool-down: Easy jog (1.0 km)
        Findings:
        F1. Distance matched the plan: 5.0 km of 5.0 km planned (As planned).
        F2. Average pace 5:43 /km over 28:36 moving time.
        F3. Average heart rate 152 bpm (zone 3), max 170 bpm.
        F4. Time in heart rate zones: Z2 13 min, Z4 15 min.
        F5. Warm-up (km 0–1): 6:30 /km, HR 135 bpm (zone 2); target up to zone 2: on target.
        F6. Tempo (km 1–4): 5:09 /km, HR 163 bpm (zone 4); target zones 3–4: on target.
        F7. Cool-down (km 4–5): 6:40 /km, HR 142 bpm (zone 2); target up to zone 2: on target.
        F8. Climbed 13 m and descended 12 m.
        Splits (moving time):
        km 1 · 6:30 /km · HR 135 · +3/−2 m
        km 2 · 5:12 /km · HR 158 · +4/−3 m
        km 3 · 5:08 /km · HR 164 · +2/−2 m
        km 4 · 5:06 /km · HR 166 · +3/−2 m
        km 5 · 6:40 /km · HR 142 · +1/−3 m
        Program:
        Plan adherence 86% (6 of 7 sessions).
        This week: 12.4 of 22.5 km done (week 3 of 8).
        Recent sessions: Mon 26 Oct Tempo run 6.2/6.0 km (on track) · Fri 23 Oct Long run 7.0/10.0 km (off plan) · Mon 19 Oct Tempo run 5.5/5.5 km (on track)
        Next: Fri 30 Oct Long run 10.0 km.
        HRV: 58 ms (−6% vs last 7 nights)
        """

    // MARK: Scenario B: easy 8.0 km, no route

    static let easySession = PlannedSession(
        date: day(10, 14),
        type: .easy,
        name: "Easy run",
        distanceKm: 8.0,
        estimatedMinutes: 50,
        effort: "Conversational",
        segments: [Segment(label: "Easy", detail: "Conversational effort", distanceKm: 8.0)],
        note: nil
    )

    static let easyRun = CompletedRun(id: "run-b", localDate: day(10, 14), distanceKm: 8.0, durationSeconds: 2_930)

    static let easySplits: [(Double, Double, Double, Double, Double)] = zip(
        [360.0, 361, 362, 364, 366, 369, 372, 376],
        zip([132.0, 134, 136, 138, 141, 144, 147, 150], [138.0, 140, 142, 145, 148, 151, 154, 158])
    ).map { ($0, $1.0, $1.1, 0, 0) }

    static let easyAnalysis = analysis(splits: easySplits, hasElevation: false, runId: "run-b")

    static let requestB = request(session: easySession, run: easyRun, analysis: easyAnalysis, recovery: .none)

    /// A short prompt for adapter and gate tests.
    static let samplePrompt = DetailedNotePromptBuilder.build(FactsBuilder.build(requestA))
}
