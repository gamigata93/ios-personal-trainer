import Foundation
import Testing
@testable import Domain

@Suite("Heart-rate profile")
struct HeartRateProfileTests {
    private let profile = WorkoutNoteFixture.profile

    @Test func boundariesAreFractionsOfTheReserve() {
        #expect(profile.reserve == 133)
        let boundaries = AssessmentRules.zoneFractions.map(profile.boundary)
        for (value, expected) in zip(boundaries, [115.5, 128.8, 142.1, 155.4, 168.7]) {
            #expect(abs(value - expected) < 1e-9)
        }
    }

    @Test func zones() {
        #expect(profile.zone(for: 100) == 1)
        #expect(profile.zone(for: 128.7) == 1)
        #expect(profile.zone(for: 128.8) == 2)
        #expect(profile.zone(for: 142.0) == 2)
        #expect(profile.zone(for: 142.1) == 3)
        #expect(profile.zone(for: 155.4) == 4)
        #expect(profile.zone(for: 168.7) == 5)
        #expect(profile.zone(for: 182) == 5)
    }

    @Test func upperBpmRoundsHalfUp() {
        #expect(profile.upperBpm(zone: 1) == 129)
        #expect(profile.upperBpm(zone: 2) == 142)
        #expect(profile.upperBpm(zone: 3) == 155)
        #expect(profile.upperBpm(zone: 4) == 169)
        #expect(profile.upperBpm(zone: 5) == nil)
    }

    @Test func realValues() {
        #expect(profile.zone(for: 138.2) == 2)  // 29 Sep
        #expect(profile.zone(for: 152.9) == 3)  // 8 Oct
        #expect(profile.zone(for: 168.97) == 5) // 20 Sep long run
    }

    @Test func observedMax() {
        let maxima: [Double?] = [169, 159, 153, 151, 153, 169, 182, 142, 172, 159]
        #expect(ObservedMaxHeartRate.value(maxima) == 182)
        // Only two runs with heart rate: 220 - 32.
        let observed = ObservedMaxHeartRate.value([170, nil, 165])
        #expect(observed == nil)
        #expect(ObservedMaxHeartRate.maxHr(observed: observed, ageYears: 32) == 188)
        // No age and too few runs: no profile.
        #expect(HeartRateProfile.make(maxHr: ObservedMaxHeartRate.maxHr(observed: nil, ageYears: nil), restingHr: 49) == nil)
        #expect(HeartRateProfile.make(maxHr: 182, restingHr: nil) == nil)
    }
}

@Suite("Distance check and assessment")
struct DistanceAndVerdictTests {
    @Test func distanceChecks() {
        let a = DistanceCheck.check(plannedKm: 6.5, doneKm: 6.2) // −4.6%
        #expect(a.isOnPlan && abs(a.deltaKm + 0.3) < 1e-9)
        #expect(DistanceCheck.check(plannedKm: 10, doneKm: 7) == .short(deltaKm: -3, percent: 30))
        let long = DistanceCheck.check(plannedKm: 7, doneKm: 8)
        #expect(long == .long(deltaKm: 1, percent: 14))
        #expect(DistanceCheck.check(plannedKm: 10, doneKm: 11).isOnPlan)
        #expect(DistanceCheck.check(plannedKm: 10, doneKm: 9).isOnPlan)
        #expect(DistanceCheck.check(plannedKm: 10, doneKm: 8.99).isShort)
    }

    @Test func blockChecks() {
        let warmUp = EffortTarget.zones(low: 1, high: 2, upperOnly: true)
        #expect(BlockEffortCheck.check(zone: 3, target: warmUp) == .slightlyHard)
        #expect(BlockEffortCheck.check(zone: 4, target: warmUp) == .tooHard)
        #expect(BlockEffortCheck.check(zone: 1, target: warmUp) == .onTarget)
        let tempo = EffortTarget.zones(low: 3, high: 4, upperOnly: false)
        #expect(BlockEffortCheck.check(zone: 4, target: tempo) == .onTarget)
        #expect(BlockEffortCheck.check(zone: 5, target: tempo) == .slightlyHard)
        #expect(BlockEffortCheck.check(zone: 2, target: tempo) == .slightlyEasy)
        #expect(BlockEffortCheck.check(zone: 1, target: tempo) == .tooEasy)
        #expect(BlockEffortCheck.check(zone: 3, target: .mixed) == .notAssessed)
        #expect(BlockEffortCheck.check(zone: nil, target: tempo) == .notAssessed)
    }

    @Test func verdicts() {
        let onPlan = DistanceCheck.onPlan(deltaKm: 0)
        #expect(WorkoutAssessment(distance: onPlan, blocks: [.onTarget, .tooHard]).verdict == .offPlan)
        #expect(WorkoutAssessment(distance: onPlan, blocks: [.slightlyHard]).verdict == .watch)
        #expect(WorkoutAssessment(distance: onPlan, blocks: [.tooEasy]).verdict == .watch)
        #expect(WorkoutAssessment(distance: onPlan, blocks: [.slightlyEasy, .onTarget]).verdict == .onTrack)
        #expect(WorkoutAssessment(distance: onPlan, blocks: [.notAssessed]).verdict == .onTrack)
        #expect(WorkoutAssessment(distance: onPlan, blocks: [.onTarget], drift: .high).verdict == .watch)
        #expect(WorkoutAssessment(distance: .check(plannedKm: 10, doneKm: 7), blocks: []).verdict == .offPlan)
        #expect(WorkoutAssessment(distance: .check(plannedKm: 10, doneKm: 8.5), blocks: []).verdict == .watch)
        #expect(WorkoutAssessment(distance: .check(plannedKm: 10, doneKm: 11.2), blocks: [.onTarget]).verdict == .watch)
        #expect(WorkoutVerdict.allCases.map(\.chipText) == ["On track", "Worth watching", "Off plan"])
    }

    @Test func effortTargetTable() {
        func target(_ detail: String, _ type: SessionType = .tempo) -> EffortTarget? {
            EffortTargetTable.target(detail: detail, sessionType: type)
        }
        #expect(target("Easy jog") == .zones(low: 1, high: 2, upperOnly: true))
        #expect(target("3 km continuous, comfortably hard") == .zones(low: 3, high: 4, upperOnly: false))
        #expect(target("Steady, last 2 km at moderate effort", .long) == .zones(low: 2, high: 3, upperOnly: true))
        #expect(target("2 x 8 min at threshold, 90 s jog recovery", .threshold) == .mixed)
        #expect(target("4 x 800 m, 400 m jog", .intervals) == .mixed)
        #expect(target("4 x 800 m, 400 m jog", .easy) == .mixed)
        #expect(target("Conversational effort", .easy) == .zones(low: 1, high: 2, upperOnly: true))
        #expect(target("Race effort") == nil)
    }
}

@Suite("Workout analyzer")
struct WorkoutAnalyzerTests {
    /// One leg per km: distance points at the boundaries, a heart-rate sample
    /// every second (the first at the max, the second at 2 x avg - max).
    static func series(
        _ legs: [(km: Double, pace: Double, avg: Double, max: Double)], pauses: [TimeSpan] = []
    ) -> WorkoutDetailSeries {
        var points = [DistancePoint(t: 0, meters: 0)]
        var heartRate: [TimedValue] = []
        var t = 0.0
        var meters = 0.0
        var pending = pauses
        for leg in legs {
            let seconds = leg.km * leg.pace
            for second in 0..<Int(seconds) {
                heartRate.append(TimedValue(t: t + Double(second), value: second == 0 ? leg.max : (second == 1 ? 2 * leg.avg - leg.max : leg.avg)))
            }
            // Pauses inside this leg add elapsed time without distance.
            var legEnd = t + seconds
            while let pause = pending.first, pause.start < legEnd {
                points.append(DistancePoint(t: pause.start, meters: meters + (pause.start - t) / seconds * leg.km * 1_000))
                points.append(DistancePoint(t: pause.end, meters: meters + (pause.start - t) / seconds * leg.km * 1_000))
                legEnd += pause.duration
                pending.removeFirst()
            }
            t = legEnd
            meters += leg.km * 1_000
            points.append(DistancePoint(t: t, meters: meters))
        }
        return WorkoutDetailSeries(
            runId: "run",
            meta: WorkoutMeta(distanceMeters: meters, elapsedSeconds: t, start: Date(timeIntervalSince1970: 0), sourceLabel: "Apple Watch"),
            distance: DistanceTimeline(points: points, source: .samples),
            heartRate: heartRate,
            pauses: pauses
        )
    }

    static let tempoLegs: [(km: Double, pace: Double, avg: Double, max: Double)] = WorkoutNoteFixture.tempoSplits.map { (1, $0.0, $0.1, $0.2) }

    @Test func scenarioATotalsSplitsAndZones() throws {
        let analysis = WorkoutAnalyzer.analyze(Self.series(Self.tempoLegs), computedAt: .distantPast)
        #expect(abs(analysis.totals.movingSeconds - 1_716) < 1e-6)
        #expect(analysis.totals.distanceKm == 5)
        #expect(WorkoutFormat.pace(try #require(analysis.totals.paceSecPerKm)) == "5:43 /km")
        #expect(AnalysisMath.rounded(try #require(analysis.avgHr)) == 152)
        #expect(analysis.maxHr == 170)
        #expect(analysis.splits.map { AnalysisMath.rounded($0.paceSecPerKm) } == [390, 312, 308, 306, 400])
        #expect(analysis.splits.map { AnalysisMath.rounded($0.avgHr ?? 0) } == [135, 158, 164, 166, 142])
        #expect(analysis.splits.compactMap(\.maxHr) == [148, 165, 168, 170, 156])
        let zones = ZoneTime.seconds(analysis, profile: WorkoutNoteFixture.profile)
        #expect(AnalysisMath.rounded(zones[1] / 60) == 13)
        #expect(AnalysisMath.rounded(zones[3] / 60) == 15)
    }

    @Test func pausedTimeIsNotMovingTime() {
        // Two pauses (60 s and 35 s): elapsed 1,811 s, moving 1,716 s.
        let pauses = [TimeSpan(start: 500, end: 560), TimeSpan(start: 1_200, end: 1_235)]
        let analysis = WorkoutAnalyzer.analyze(Self.series(Self.tempoLegs, pauses: pauses), computedAt: .distantPast)
        #expect(abs(analysis.totals.elapsedSeconds - 1_811) < 1e-6)
        #expect(abs(analysis.totals.movingSeconds - 1_716) < 1e-6)
        #expect(analysis.totals.pauseCount == 2 && analysis.totals.pausedSeconds == 95)
        #expect(analysis.splits.map { AnalysisMath.rounded($0.movingSeconds) } == [390, 312, 308, 306, 400])
    }

    @Test func aPauseInsideAKilometre() {
        // The km spans 410 s of elapsed time with a 20 s pause: moving 390 s, 6:30 /km.
        let series = WorkoutDetailSeries(
            runId: "run",
            meta: WorkoutMeta(distanceMeters: 1_000, elapsedSeconds: 410, start: .distantPast, sourceLabel: "Watch"),
            distance: DistanceTimeline(points: [
                DistancePoint(t: 0, meters: 0), DistancePoint(t: 200, meters: 500), DistancePoint(t: 220, meters: 500), DistancePoint(t: 410, meters: 1_000),
            ], source: .samples),
            pauses: [TimeSpan(start: 200, end: 220)]
        )
        let split = WorkoutAnalyzer.analyze(series, computedAt: .distantPast).splits[0]
        #expect(split.movingSeconds == 390)
        #expect(WorkoutFormat.pace(split.paceSecPerKm) == "6:30 /km")
    }

    @Test func aPartialLastSplit() {
        // 5.4 km: the last 0.4 km takes 130 s (325 s/km).
        let legs = Array(Self.tempoLegs) + [(km: 0.4, pace: 325, avg: 150, max: 155)]
        let analysis = WorkoutAnalyzer.analyze(Self.series(legs), computedAt: .distantPast)
        let last = analysis.splits[5]
        #expect(analysis.splits.count == 6)
        #expect(abs(last.distanceKm - 0.4) < 1e-9 && abs(last.movingSeconds - 130) < 1e-6)
        #expect(FactsBuilder.splitRow(last).hasPrefix("km 6 (0.4 km) · 5:25 /km"))
    }

    @Test func routeDistanceIsScaledToTheWorkoutTotal() {
        let series = WorkoutDetailSeries(
            runId: "run",
            meta: WorkoutMeta(distanceMeters: 2_000, elapsedSeconds: 720, start: .distantPast, sourceLabel: "Watch"),
            distance: DistanceTimeline(points: [DistancePoint(t: 0, meters: 0), DistancePoint(t: 720, meters: 1_800)], source: .route)
        )
        let analysis = WorkoutAnalyzer.analyze(series, computedAt: .distantPast)
        #expect(analysis.totals.distanceKm == 2)
        #expect(analysis.splits.map(\.movingSeconds) == [360, 360])
        #expect(analysis.dataQuality.hasRoute && !analysis.dataQuality.hasHr)
    }

    @Test func noSeriesStillGivesTotals() {
        let series = WorkoutDetailSeries(runId: "run", meta: WorkoutMeta(distanceMeters: 5_000, elapsedSeconds: 1_800, start: .distantPast, sourceLabel: "App"))
        let analysis = WorkoutAnalyzer.analyze(series, computedAt: .distantPast)
        #expect(analysis.totals.distanceKm == 5 && analysis.totals.movingSeconds == 1_800)
        #expect(analysis.splits.isEmpty && analysis.avgHr == nil && analysis.hrHistogram.isEmpty)
    }

    @Test func heartRateHoldsThirtySecondsAtMost() {
        // 150 bpm at t 0 then nothing until 120 bpm at t 100: 150 counts for 30 s only.
        let step = StepSeries(samples: [TimedValue(t: 0, value: 150), TimedValue(t: 100, value: 120)], end: 130)
        #expect(step.average(from: 0, to: 130) == 135) // (150 x 30 + 120 x 30) / 60
    }

    @Test func elevationIsSmoothedAndSmallStepsIgnored() throws {
        // A steady 10 m climb then a 4 m descent, sampled every 10 s.
        let altitude = (0...20).map { index -> TimedValue in
            let x = Double(index)
            let value: Double = index <= 10 ? 100 + x : 110 - (x - 10) * 0.4
            return TimedValue(t: x * 10, value: value)
        }
        let steps = try #require(ElevationSteps(altitude: altitude))
        #expect(steps.totalGain > 8 && steps.totalGain <= 10)
        #expect(steps.totalLoss > 2 && steps.totalLoss <= 4)
        // Wobbles under 0.5 m never count.
        let flat = (0...20).map { index -> TimedValue in
            let wobble: Double = index % 2 == 0 ? 0.2 : -0.2
            return TimedValue(t: Double(index), value: 100 + wobble)
        }
        #expect(ElevationSteps(altitude: flat)?.totalGain == 0)
    }
}

@Suite("Drift, split style and fade")
struct RunMetricsTests {
    @Test func scenarioB() throws {
        let analysis = WorkoutNoteFixture.easyAnalysis
        let drift = try #require(HeartRateDrift.measure(analysis, type: .easy))
        // k = 2: first (132 + 134) / 2 = 133, last (147 + 150) / 2 = 148.5: +11.65%.
        #expect(abs(drift.percent - 15.5 / 133 * 100) < 1e-9 && drift.band == .high)
        let style = try #require(SplitStyle.measure(analysis, type: .easy))
        #expect(style.kind == .positive && style.firstHalfPace == 361.75 && style.secondHalfPace == 370.75)
        // 374 vs 363.67: +2.84%, not a fade.
        #expect(Fade.measure(analysis, type: .easy) == nil)
        // Not for tempo sessions.
        #expect(HeartRateDrift.measure(analysis, type: .tempo) == nil)
        #expect(SplitStyle.measure(analysis, type: .tempo) == nil)
    }

    @Test func boundaries() {
        #expect(SplitStyle.kind(first: 300, second: 306) == .even)        // exactly 2.0%
        #expect(SplitStyle.kind(first: 300, second: 306.03) == .positive) // 2.01%
        #expect(SplitStyle.kind(first: 300, second: 293.97) == .negative)
        #expect(HeartRateDrift.band(5.0) == .low)
        #expect(HeartRateDrift.band(5.01) == .moderate)
        #expect(HeartRateDrift.band(8.0) == .moderate)
        #expect(HeartRateDrift.band(8.01) == .high)
        // Exactly 3.0% slower over the last 2 km is not a fade; 3.1% is.
        func analysis(_ paces: [Double]) -> WorkoutAnalysis {
            WorkoutNoteFixture.analysis(splits: paces.map { ($0, 140, 145, 0, 0) }, hasElevation: false)
        }
        #expect(Fade.measure(analysis([300, 300, 300, 309, 309]), type: .long) == nil)
        #expect(Fade.measure(analysis([300, 300, 300, 309.3, 309.3]), type: .long) != nil)
    }
}

@Suite("Plan alignment")
struct PlanAlignmentTests {
    @Test func scenarioABlocks() throws {
        let blocks = PlanAlignment.align(session: WorkoutNoteFixture.tempoSession, analysis: WorkoutNoteFixture.tempoAnalysis, profile: WorkoutNoteFixture.profile)
        #expect(blocks.map(\.actualStartKm) == [0, 1, 4])
        #expect(blocks.map(\.actualEndKm) == [1, 4, 5])
        #expect(blocks.map { WorkoutFormat.pace($0.paceSecPerKm ?? 0) } == ["6:30 /km", "5:09 /km", "6:40 /km"])
        #expect(blocks.map { AnalysisMath.rounded($0.avgHr ?? 0) } == [135, 163, 142])
        #expect(blocks.map(\.zone) == [2, 4, 2])
        #expect(blocks.map(\.check) == [.onTarget, .onTarget, .onTarget])
        #expect(WorkoutReview(session: WorkoutNoteFixture.tempoSession, run: WorkoutNoteFixture.tempoRun, analysis: WorkoutNoteFixture.tempoAnalysis, profile: WorkoutNoteFixture.profile).verdict == .onTrack)
    }

    @Test func aShorterRunMovesTheBoundaries() throws {
        // 4.8 km against 5.0: boundaries at 0.96 and 3.84 km.
        let splits: [WorkoutAnalysis.Split] = [
            .init(index: 1, distanceKm: 1, movingSeconds: 400, paceSecPerKm: 400),
            .init(index: 2, distanceKm: 1, movingSeconds: 300, paceSecPerKm: 300),
            .init(index: 3, distanceKm: 1, movingSeconds: 300, paceSecPerKm: 300),
            .init(index: 4, distanceKm: 1, movingSeconds: 300, paceSecPerKm: 300),
            .init(index: 5, distanceKm: 0.8, movingSeconds: 240, paceSecPerKm: 300),
        ]
        let analysis = WorkoutAnalysis(
            runId: "r", computedAt: .distantPast, dataQuality: .none,
            totals: .init(distanceKm: 4.8, movingSeconds: 1_540, elapsedSeconds: 1_540, pauseCount: 0, pausedSeconds: 0), splits: splits
        )
        let blocks = PlanAlignment.align(session: WorkoutNoteFixture.tempoSession, analysis: analysis, profile: nil)
        #expect(abs(blocks[1].actualStartKm - 0.96) < 1e-9 && abs(blocks[1].actualEndKm - 3.84) < 1e-9)
        // 16 + 300 + 300 + 252 = 868 s over 2.88 km = 301.4 s/km.
        let pace = try #require(blocks[1].paceSecPerKm)
        #expect(abs(pace - 868 / 2.88) < 1e-9)
        #expect(WorkoutFormat.pace(pace) == "5:01 /km")
        #expect(Findings.blockText(blocks[1]).hasPrefix("Tempo (km 1–3.8): 5:01 /km; target zones 3–4: not assessed"))
    }
}

@Suite("Findings and facts")
struct FactsTests {
    @Test func scenarioAFacts() {
        let facts = FactsBuilder.build(WorkoutNoteFixture.requestA)
        #expect(facts.text == WorkoutNoteFixture.factsA)
        // Drift, split style and fade are not produced for a tempo session.
        #expect(!facts.text.contains("drift") && !facts.text.contains("Pace was") && !facts.text.contains("slowed"))
    }

    @Test func theHashIgnoresProgramAndRecovery() {
        let a = FactsBuilder.build(WorkoutNoteFixture.requestA)
        let other = FactsBuilder.build(WorkoutNoteFixture.request(recovery: RecoveryFacts(hrv: HRVFact(valueMs: 70, deltaPercent: 10))))
        #expect(a.text != other.text)
        #expect(SHA256Digest.hex(a.hashText) == SHA256Digest.hex(other.hashText))
        #expect(!a.hashText.contains("Program:") && !a.hashText.contains("HRV"))
        // A changed average heart rate changes it.
        var splits = WorkoutNoteFixture.tempoSplits
        splits[0].1 = 137
        let changed = FactsBuilder.build(WorkoutNoteFixture.request(analysis: WorkoutNoteFixture.analysis(splits: splits)))
        #expect(SHA256Digest.hex(changed.hashText) != SHA256Digest.hex(a.hashText))
    }

    @Test func pauseFindings() {
        let analysis = WorkoutNoteFixture.analysis(splits: WorkoutNoteFixture.tempoSplits, pauses: (2, 95))
        let texts = Findings.make(WorkoutNoteFixture.request(analysis: analysis).review).map(\.text)
        #expect(texts[1] == "Average pace 5:43 /km over 28:36 moving time (30:11 elapsed).")
        #expect(texts[2] == "Paused 2 times for 1:35.")
        let one = WorkoutNoteFixture.analysis(splits: WorkoutNoteFixture.tempoSplits, pauses: (1, 60))
        #expect(Findings.make(WorkoutNoteFixture.request(analysis: one).review).map(\.text)[2] == "Paused 1 time for 1:00.")
    }

    @Test func scenarioBFindings() {
        let texts = WorkoutNoteFixture.requestB.findings.map(\.text)
        #expect(texts.contains("Average pace 6:06 /km over 48:50 moving time."))
        #expect(texts.contains("Average heart rate 140 bpm (zone 2), max 158 bpm."))
        #expect(texts.contains("Pace was positive: first half 6:02 /km, second half 6:11 /km (+9 s/km)."))
        #expect(texts.contains("Heart rate drift +12% (high) from the first to the last third."))
        #expect(texts.contains("Time in heart rate zones: Z2 30 min, Z3 19 min."))
        #expect(!texts.contains { $0.hasPrefix("Pace slowed") })
        #expect(!texts.contains { $0.hasPrefix("Climbed") })
        #expect(WorkoutNoteFixture.requestB.review.verdict == .watch)
        let facts = FactsBuilder.build(WorkoutNoteFixture.requestB).text
        #expect(facts.contains("\nkm 1 · 6:00 /km · HR 132\n"))
    }

    @Test func noHeartRateSkipsTheHeartRateFindings() {
        let analysis = WorkoutNoteFixture.analysis(splits: WorkoutNoteFixture.tempoSplits, hasHr: false)
        let texts = Findings.make(WorkoutNoteFixture.request(analysis: analysis).review).map(\.text)
        #expect(!texts.contains { $0.hasPrefix("Average heart rate") || $0.hasPrefix("Time in heart rate zones") })
        #expect(texts.contains("Warm-up (km 0–1): 6:30 /km; target up to zone 2: not assessed."))
    }

    @Test func mixedBlocks() {
        let session = PlannedSession(
            date: WorkoutNoteFixture.day(10, 12), type: .threshold, name: "Threshold reps", distanceKm: 5, estimatedMinutes: 30, effort: "Threshold",
            segments: [
                Segment(label: "Warm-up", detail: "Easy jog", distanceKm: 1),
                Segment(label: "Threshold", detail: "2 x 8 min at threshold, 90 s jog recovery", distanceKm: 3),
                Segment(label: "Cool-down", detail: "Easy jog", distanceKm: 1),
            ],
            note: nil
        )
        let texts = WorkoutNoteFixture.request(session: session).findings.map(\.text)
        #expect(texts.contains("Threshold (km 1–4): reps and recoveries mixed, effort not assessed."))
    }

    @Test func compactionLevels() {
        // A 21-split run.
        let splits = (0..<21).map { _ in (330.0, 150.0, 155.0, 2.0, 1.0) }
        let session = PlannedSession(
            date: WorkoutNoteFixture.day(10, 16), type: .long, name: "Long run", distanceKm: 21, estimatedMinutes: 120, effort: "Steady",
            segments: [Segment(label: "Long run", detail: "Steady effort", distanceKm: 21)],
            note: nil
        )
        let request = WorkoutNoteFixture.request(session: session, analysis: WorkoutNoteFixture.analysis(splits: splits))
        let full = FactsBuilder.build(request, level: 0)
        let pairs = FactsBuilder.build(request, level: 1)
        let fives = FactsBuilder.build(request, level: 2)
        let bare = FactsBuilder.build(request, level: 3)
        #expect(full.text.contains("\nkm 21 · 5:30 /km · HR 150 · +2/−1 m"))
        #expect(pairs.text.contains("\nkm 1–2 · 5:30 /km · HR 150 · +4/−2 m\n"))
        #expect(pairs.text.contains("\nkm 21 · 5:30 /km · HR 150 · +2/−1 m"))
        #expect(fives.text.contains("\nkm 1–5 · 5:30 /km · HR 150 · +10/−5 m\n"))
        #expect(fives.text.contains("Recent sessions: Mon 26 Oct Tempo run 6.2/6.0 km (on track)\n"))
        #expect(!bare.text.contains("Splits") && !bare.text.contains("Recent sessions") && bare.text.contains("Findings:"))
        #expect(bare.text.contains("Plan adherence 86%"))

        // The smallest level that fits wins (fake estimator: one token per line).
        let byLines: (WorkoutFacts) -> Int = { $0.lines.count }
        let budgetFor = { (tokens: Int) in Int((Double(tokens + AnalysisRules.outputReserveTokens) / AnalysisRules.factsBudgetShare).rounded(.up)) }
        #expect(DetailedNotePromptBuilder.fittingFacts(request, contextSize: budgetFor(full.lines.count), estimate: byLines)?.level == 0)
        #expect(DetailedNotePromptBuilder.fittingFacts(request, contextSize: budgetFor(full.lines.count - 1), estimate: byLines)?.level == 1)
        #expect(DetailedNotePromptBuilder.fittingFacts(request, contextSize: budgetFor(pairs.lines.count - 1), estimate: byLines)?.level == 2)
        #expect(DetailedNotePromptBuilder.fittingFacts(request, contextSize: budgetFor(bare.lines.count - 1), estimate: byLines) == nil)
        // The default context (20,000) takes the full facts.
        #expect(DetailedNotePromptBuilder.fittingFacts(request, contextSize: nil)?.level == 0)
        // A small on-device context forces a higher level with the real estimator.
        let tokens0 = DetailedNotePromptBuilder.estimatedTokens(full)
        let tokens1 = DetailedNotePromptBuilder.estimatedTokens(pairs)
        let squeezed = DetailedNotePromptBuilder.fittingFacts(request, contextSize: budgetFor(tokens1))
        #expect(tokens1 < tokens0 && squeezed?.level == 1)
    }

    @Test func promptAndRevisionNotes() {
        let facts = FactsBuilder.build(WorkoutNoteFixture.requestA)
        let prompt = DetailedNotePromptBuilder.build(facts, revisionNotes: ["Headline is over 60 characters"])
        #expect(prompt.instructions.hasPrefix("You are a running coach writing a post-workout note for one athlete. Use ONLY the facts."))
        #expect(prompt.instructions.contains("headline 60, how it went 320, versus the plan 320, the program 280, next step 200 characters."))
        #expect(prompt.instructions.contains(
            "Quote km marks and ranges exactly as written in the facts (for example km 1.4–4.3); never invent a km mark."
        ))
        #expect(prompt.instructions.contains("When it fits, connect the next step to the Next session in the facts."))
        #expect(prompt.text.hasSuffix("\n\nFix these problems:\nHeadline is over 60 characters"))
        #expect(!DetailedNotePromptBuilder.build(facts).text.contains("Fix these problems"))
    }
}

@Suite("Detailed note guard")
struct DetailedNoteGuardTests {
    private let facts = WorkoutNoteFixture.factsA

    private func note(howItWent: String = "You ran 5.0 km at 5:43 /km.", headline: String = "Steady") -> CoachNote {
        CoachNote(headline: headline, howItWent: howItWent, versusPlan: "Blocks on target.", programStatus: "On track.", nextStep: "Rest.")
    }

    private func issues(_ note: CoachNote) -> [DetailedNoteGuard.Issue] {
        DetailedNoteGuard.issues(note, facts: facts, runDistanceKm: 5)
    }

    @Test func supportedNumbersAndPacesPass() {
        #expect(issues(note(howItWent: "Your second km was 5:12 /km, and km 0–1 was easy.")).isEmpty)
        #expect(issues(note(howItWent: "You ran 6.2 of 6.5 km at 5:30 /km.")) != [])
    }

    @Test func unsupportedPace() {
        #expect(issues(note(howItWent: "Your second km was 5:13 /km.")) == [.unsupportedPace("5:13")])
    }

    @Test func lengths() {
        #expect(issues(note(headline: String(repeating: "a", count: 60))).isEmpty)
        #expect(issues(note(headline: String(repeating: "a", count: 61))) == [.tooLong(field: "Headline", limit: 60)])
        #expect(issues(note(howItWent: String(repeating: "a", count: 320))).isEmpty)
        #expect(issues(note(howItWent: String(repeating: "a", count: 321))) == [.tooLong(field: "How it went", limit: 320)])
    }
}

@Suite("Rule-based note")
struct TemplateDetailedNoteTests {
    @Test func scenarioA() {
        let note = TemplateDetailedNoteWriter.write(WorkoutNoteFixture.requestA)
        #expect(note.headline == "Right on plan")
        #expect(note.howItWent == "You ran 5.0 km at 5:43 /km, and every block of the session landed in its target heart rate zone.")
        #expect(note.versusPlan == "Warm-up (km 0–1): 6:30 /km, HR 135 bpm (zone 2); target up to zone 2: on target. "
            + "Tempo (km 1–4): 5:09 /km, HR 163 bpm (zone 4); target zones 3–4: on target. "
            + "Cool-down (km 4–5): 6:40 /km, HR 142 bpm (zone 2); target up to zone 2: on target.")
        #expect(note.programStatus == "Plan adherence is 86% (6 of 7 sessions). One of your last 3 sessions was cut short.")
        #expect(note.nextStep == "Recover well before the next hard session. HRV is lower than your recent nights, so keep tomorrow easy.")
        // It passes the guard against its own facts.
        #expect(DetailedNoteGuard.issues(note, facts: WorkoutNoteFixture.factsA, runDistanceKm: 5).isEmpty)
    }

    @Test func scenarioB() {
        let note = TemplateDetailedNoteWriter.write(WorkoutNoteFixture.requestB)
        #expect(note.headline == "Worth a closer look")
        #expect(note.howItWent == "You ran 8.0 km at 6:06 /km, and your heart rate stayed in its target zone. "
            + "Your heart rate drifted +12% from the first to the last third.")
        #expect(note.versusPlan == "Pace was positive: first half 6:02 /km, second half 6:11 /km (+9 s/km).")
        #expect(note.nextStep == "Keep the next easy run just as relaxed.")
    }

    @Test func aShortfallWinsOverEffort() {
        let short = WorkoutNoteFixture.analysis(splits: Array(WorkoutNoteFixture.tempoSplits.prefix(3)))
        let note = TemplateDetailedNoteWriter.write(WorkoutNoteFixture.request(analysis: short, recovery: .none))
        #expect(note.headline == "Off plan")
        #expect(note.nextStep == "Don't make it up. Pick the plan up with the next session.")
    }
}

@Suite("SHA-256")
struct SHA256Tests {
    @Test func knownVectors() {
        #expect(SHA256Digest.hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(SHA256Digest.hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(SHA256Digest.hex(String(repeating: "a", count: 1_000)).count == 64)
    }
}

@Suite("Lab sample")
struct LabSampleTests {
    @Test func theSampleIsScenarioA() {
        #expect(FactsBuilder.build(.sampleTempo).text == WorkoutNoteFixture.factsA)
    }
}
