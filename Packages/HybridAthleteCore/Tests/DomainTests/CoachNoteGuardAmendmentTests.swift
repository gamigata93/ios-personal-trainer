import Foundation
import Testing
@testable import Domain

/// F1: the facts of a real 5.7 km tempo run (planned 6.0 km in 1.5/3.0/1.5 km
/// blocks), with block findings at km 0–1.4, 1.4–4.3 and 4.3–5.7.
enum GuardFixture {
    static let runKm = 5.7

    static let factsF1 = """
        Session: Tempo run (Tempo)
        Plan source: template-v1
        Plan position: week 3 of 8, base phase, 39 days to race.
        Planned: 6.0 km
        Planned effort: Comfortably hard
        Planned blocks:
        - Warm-up: Easy jog (1.5 km)
        - Tempo: 3 km continuous, comfortably hard (3.0 km)
        - Cool-down: Easy jog (1.5 km)
        Findings:
        F1. Distance close to the plan: 5.7 km of 6.0 km planned (−5%).
        F2. Average pace 6:00 /km over 34:12 moving time.
        F3. Average heart rate 158 bpm (zone 4), max 172 bpm.
        F4. Time in heart rate zones: Z4 34 min.
        F5. Warm-up (km 0–1.4): 6:00 /km, HR 158 bpm (zone 4); target up to zone 2: above target.
        F6. Tempo (km 1.4–4.3): 6:00 /km, HR 158 bpm (zone 4); target zones 3–4: on target.
        F7. Cool-down (km 4.3–5.7): 6:00 /km, HR 158 bpm (zone 4); target up to zone 2: above target.
        Splits (moving time):
        km 1 · 6:00 /km · HR 158
        km 2 · 6:00 /km · HR 158
        km 3 · 6:00 /km · HR 158
        km 4 · 6:00 /km · HR 158
        km 5 · 6:00 /km · HR 158
        km 6 (0.7 km) · 6:00 /km · HR 158
        Program:
        Plan adherence 86% (6 of 7 sessions).
        This week: 12.4 of 22.5 km done (week 3 of 8).
        Next: Fri 30 Oct Long run 10.0 km.
        """

    /// A note that quotes the three block ranges, the paces and the zones.
    static let goodNote = CoachNote(
        headline: "Even pace, but the easy blocks ran hot",
        howItWent: "You ran 5.7 km at an even 6:00 /km with heart rate around 158 bpm, which is zone 4 for you.",
        versusPlan: "The tempo (km 1.4–4.3) hit target zones 3–4. The warm-up (km 0–1.4) and cool-down (km 4.3–5.7) were above zone 2.",
        programStatus: "Adherence is 86% with 12.4 of 22.5 km done in week 3 of 8.",
        nextStep: "Keep Friday's long run of 10.0 km truly easy and let the first km settle."
    )

    static func kmIssues(_ text: String, facts: String = factsF1, runKm: Double = runKm) -> [String] {
        DetailedNoteGuard.badKmReferences(in: text, facts: facts, runDistanceKm: runKm)
    }

    static func tenths(_ values: [Double]) -> Set<Int> {
        Set(values.map { Int(($0 * 10).rounded()) })
    }
}

@Suite("Note guard: km marks and zones")
struct KmAndZoneGuardTests {
    private typealias G = GuardFixture

    @Test func theAllowedSets() {
        let marks = DetailedNoteGuard.kmMarks(facts: G.factsF1, runDistanceKm: G.runKm)
        #expect(G.tenths(marks) == G.tenths([0, 1.4, 4.3, 5.7, 1, 2, 3, 4, 5, 6]))
        let zones = Set(DetailedNoteGuard.references(DetailedNoteGuard.zonePattern, in: G.factsF1).flatMap(\.values))
        #expect(zones == [2, 3, 4])
    }

    @Test(arguments: [
        "km 0–1.4", "km 1.4–4.3", "km 4.3-5.7", "km 3", "km 6", "kilometre 3", "kilometres 1.4–4.3", "km 5.0", "km 2–4",
        "km 1.4—4.3", "KM 3", "kilometer 2", "kilometers 1-2", "km 0",
    ])
    func validKmReferences(_ text: String) {
        #expect(G.kmIssues("Look at \(text) again.").isEmpty)
    }

    @Test(arguments: ["km 7", "km 0.5", "km 4–2", "kilometre 8", "km 5.8"])
    func invalidKmReferences(_ text: String) {
        #expect(G.kmIssues("Look at \(text) again.") == [text])
    }

    @Test func distancesAreNotMarks() {
        #expect(G.kmIssues("You ran 5.7 km.").isEmpty)
        let note = CoachNote(headline: "A", howItWent: "A 6.2 km run.", versusPlan: "B.", programStatus: "C.", nextStep: "D.")
        #expect(DetailedNoteGuard.issues(note, facts: G.factsF1, runDistanceKm: G.runKm) == [.unsupportedNumber("6.2")])
    }

    @Test(arguments: ["zone 2", "zone 3", "zone 4", "zones 3–4", "Zone 4", "zones 3-4"])
    func validZones(_ text: String) {
        #expect(DetailedNoteGuard.badZones(in: "You were in \(text).", facts: G.factsF1).isEmpty)
    }

    @Test(arguments: ["zone 5", "zone 1", "zones 4–3", "zones 2–5"])
    func invalidZones(_ text: String) {
        #expect(DetailedNoteGuard.badZones(in: "You were in \(text).", facts: G.factsF1) == [text])
    }

    @Test func numbersInsideReferencesAreNotFlaggedTwice() {
        #expect(DetailedNoteGuard.unsupportedNumbers(in: "Tempo (km 1.4–4.3) was 6:00 /km", facts: G.factsF1).isEmpty)
        // An invalid mark is reported once, as a mark.
        let note = CoachNote(headline: "A", howItWent: "You faded at km 7 in zone 5.", versusPlan: "B.", programStatus: "C.", nextStep: "D.")
        #expect(DetailedNoteGuard.issues(note, facts: G.factsF1, runDistanceKm: G.runKm) == [.badKmReference("km 7"), .badZone("zone 5")])
    }

    @Test func pacesAndLengthsAreUnchanged() {
        #expect(DetailedNoteGuard.unsupportedPaces(in: "You held 6:00 /km.", facts: G.factsF1).isEmpty)
        #expect(DetailedNoteGuard.unsupportedPaces(in: "You held 6:05 /km.", facts: G.factsF1) == ["6:05"])
        func headline(_ count: Int) -> [DetailedNoteGuard.Issue] {
            let note = CoachNote(headline: String(repeating: "a", count: count), howItWent: "A.", versusPlan: "B.", programStatus: "C.", nextStep: "D.")
            return DetailedNoteGuard.issues(note, facts: G.factsF1, runDistanceKm: G.runKm)
        }
        #expect(headline(60).isEmpty)
        #expect(headline(61) == [.tooLong(field: "Headline", limit: 60)])
    }

    @Test func aCompleteNotePassesWithZeroIssues() {
        #expect(DetailedNoteGuard.issues(G.goodNote, facts: G.factsF1, runDistanceKm: G.runKm) == [])
    }

    @Test func revisionNoteTexts() {
        #expect(DetailedNoteGuard.Issue.badKmReference("km 7").message == "km mark km 7 is not in the facts")
        #expect(DetailedNoteGuard.Issue.badZone("zone 5").message == "zone zone 5 is not in the facts")
        #expect(DetailedNoteGuard.Issue.unsupportedPace("6:05").message == "pace 6:05 is not in the facts")
        #expect(DetailedNoteGuard.Issue.unsupportedNumber("6.2").message == "number 6.2 is not in the facts")
        #expect(DetailedNoteGuard.Issue.tooLong(field: "Headline", limit: 60).message == "Headline is over 60 characters")
    }

    // MARK: Compaction levels change K

    /// The 5.7 km tempo as a real request: six splits, the last 0.7 km.
    private static let request: WorkoutNoteRequest = {
        let session = PlannedSession(
            date: WorkoutNoteFixture.day(10, 12), type: .tempo, name: "Tempo run", distanceKm: 6.0, estimatedMinutes: 36,
            effort: "Comfortably hard",
            segments: [
                Segment(label: "Warm-up", detail: "Easy jog", distanceKm: 1.5),
                Segment(label: "Tempo", detail: "3 km continuous, comfortably hard", distanceKm: 3.0),
                Segment(label: "Cool-down", detail: "Easy jog", distanceKm: 1.5),
            ],
            note: nil
        )
        let legs: [(km: Double, pace: Double, hr: Double)] = [(1, 390, 135), (1, 312, 158), (1, 308, 164), (1, 306, 166), (1, 330, 150), (0.7, 400, 142)]
        let splits = legs.enumerated().map { index, leg in
            WorkoutAnalysis.Split(
                index: index + 1, distanceKm: leg.km, movingSeconds: leg.km * leg.pace, paceSecPerKm: leg.pace,
                avgHr: leg.hr, maxHr: leg.hr + 6, gainM: 1, lossM: 1
            )
        }
        let moving = splits.map(\.movingSeconds).reduce(0, +)
        let analysis = WorkoutAnalysis(
            runId: "run-f1", computedAt: .distantPast,
            dataQuality: WorkoutAnalysis.DataQuality(hasHr: true, hasRoute: true, hasDistanceSeries: true, hasCadence: false, hasPower: false),
            totals: WorkoutAnalysis.Totals(distanceKm: 5.7, movingSeconds: moving, elapsedSeconds: moving, pauseCount: 0, pausedSeconds: 0),
            splits: splits,
            hrHistogram: splits.map { WorkoutAnalysis.HRBin(centerBpm: Int($0.avgHr ?? 0), seconds: $0.movingSeconds) },
            avgHr: splits.map { ($0.avgHr ?? 0) * $0.movingSeconds }.reduce(0, +) / moving,
            maxHr: 172, elevationGainM: 6, elevationLossM: 6, sourceLabel: "Apple Watch"
        )
        let run = CompletedRun(id: "run-f1", localDate: session.date, distanceKm: 5.7, durationSeconds: moving)
        return WorkoutNoteRequest(
            review: WorkoutReview(session: session, run: run, analysis: analysis, profile: WorkoutNoteFixture.profile),
            planSource: "template-v1", program: WorkoutNoteFixture.program, recovery: RecoveryFacts()
        )
    }()

    private func marks(level: Int) -> (facts: String, k: Set<Int>) {
        let facts = FactsBuilder.build(Self.request, level: level).text
        return (facts, G.tenths(DetailedNoteGuard.kmMarks(facts: facts, runDistanceKm: 5.7)))
    }

    @Test func levelZeroHasEverySplitAndTheBlockBounds() {
        let (facts, k) = marks(level: 0)
        #expect(facts.contains("Warm-up (km 0–1.4)") && facts.contains("Tempo (km 1.4–4.3)") && facts.contains("Cool-down (km 4.3–5.7)"))
        #expect(k == G.tenths([0, 1.4, 4.3, 5.7, 1, 2, 3, 4, 5, 6]))
    }

    @Test func levelOnePairs() {
        let (facts, k) = marks(level: 1)
        #expect(facts.contains("\nkm 1–2 · ") && facts.contains("\nkm 3–4 · ") && facts.contains("\nkm 5–6 ("))
        #expect(k == G.tenths([0, 1.4, 4.3, 5.7, 1, 2, 3, 4, 5, 6]))
        #expect(G.kmIssues("km 3", facts: facts, runKm: 5.7).isEmpty)
    }

    @Test func levelTwoFiveKmGroups() {
        let (facts, k) = marks(level: 2)
        #expect(facts.contains("\nkm 1–5 · ") && facts.contains("\nkm 6 (0.7 km) · "))
        #expect(k == G.tenths([0, 1.4, 4.3, 5.7, 1, 5, 6]))
        #expect(G.kmIssues("At km 3 you eased.", facts: facts, runKm: 5.7) == ["km 3"])
        #expect(G.kmIssues("Over km 1–5 you held it.", facts: facts, runKm: 5.7).isEmpty)
    }

    @Test func levelThreeHasOnlyTheBlockBounds() {
        let (facts, k) = marks(level: 3)
        #expect(k == G.tenths([0, 1.4, 4.3, 5.7]))
        #expect(G.kmIssues("At km 6 you stopped.", facts: facts, runKm: 5.7) == ["km 6"])
    }
}

@Suite("Facts: Next and recent sessions")
struct NextSessionFactsTests {
    private typealias F = EditPlanFixture

    private func status(
        plan: TrainingPlan = F.base, runs: [CompletedRun] = F.runs, today: LocalDate, runDate: LocalDate? = nil
    ) -> ProgramStatus {
        ProgramStatus.make(plan: plan, runs: runs, verdicts: [:], today: today, runDate: runDate ?? today)
    }

    private func nextLine(_ status: ProgramStatus) -> String? {
        FactsBuilder.programLines(status, recentCount: 3).first { $0.hasPrefix("Next:") }
    }

    @Test func todaysUnfinishedSessionIsNext() {
        #expect(nextLine(status(today: F.day(10, 28))) == "Next: today (Wed 28 Oct) Easy run 6.5 km.")
    }

    @Test func todaysCompletedOrMissedSessionIsSkipped() throws {
        let done = status(runs: F.runs + [F.run(F.day(10, 28), 6.2)], today: F.day(10, 28))
        #expect(nextLine(done) == "Next: Fri 30 Oct Long run 10.0 km.")
        let missed = try #require(PlanEditApplier.apply(.markMissed(sessionId: F.id(10, 28)), to: F.base))
        #expect(nextLine(status(plan: missed, today: F.day(10, 28))) == "Next: Fri 30 Oct Long run 10.0 km.")
    }

    @Test func tomorrow() {
        #expect(nextLine(status(today: F.day(10, 29))) == "Next: tomorrow (Fri 30 Oct) Long run 10.0 km.")
    }

    @Test func aMovedSessionCountsByItsCurrentDate() throws {
        let moved = try #require(PlanEditApplier.apply(.move(sessionId: F.id(10, 30), from: F.day(10, 30), to: F.day(10, 31)), to: F.base))
        #expect(nextLine(status(plan: moved, today: F.day(10, 29))) == "Next: Sat 31 Oct Long run 10.0 km.")
    }

    @Test func nothingLeftOmitsTheLine() {
        #expect(nextLine(status(today: F.day(12, 5))) == nil)
    }

    @Test func aCompletedSessionIsSkippedAndFarAwayHasNoTomorrowWording() {
        // Sun 25 Oct: Mon 26 Oct is already completed (its run is in the list).
        #expect(nextLine(status(today: F.day(10, 25))) == "Next: Wed 28 Oct Easy run 6.5 km.")
    }

    @Test func recentSessionsNeverFollowTheDescribedRun() {
        let runs = F.runs + [F.run(F.day(10, 28), 6.2)]
        let forMonday = status(runs: runs, today: F.day(10, 28), runDate: F.day(10, 26))
        #expect(forMonday.recent.map(\.date) == [F.day(10, 26), F.day(10, 23), F.day(10, 19)])
        let line = FactsBuilder.programLines(forMonday, recentCount: 3).first { $0.hasPrefix("Recent sessions:") }
        #expect(line?.hasPrefix("Recent sessions: Mon 26 Oct ") == true)
        #expect(line?.contains("Wed 28 Oct") == false)
        let forFriday = status(runs: runs, today: F.day(10, 28), runDate: F.day(10, 23))
        #expect(forFriday.recent.map(\.date) == [F.day(10, 23), F.day(10, 19), F.day(10, 16)])
        // Fewer than 3 is fine.
        let first = status(runs: runs, today: F.day(10, 28), runDate: F.day(10, 12))
        #expect(first.recent.map(\.date) == [F.day(10, 12)])
    }

    @Test func theHashIgnoresNextAndRecentSessions() {
        let a = WorkoutNoteFixture.requestA
        let p = a.program
        let changed = ProgramStatus(
            completedCount: p.completedCount, dueCount: p.dueCount, weekIndex: p.weekIndex, weeksTotal: p.weeksTotal,
            kmDoneThisWeek: p.kmDoneThisWeek, kmPlannedThisWeek: p.kmPlannedThisWeek, recent: Array(p.recent.suffix(1)),
            next: ProgramStatus.NextSession(date: F.day(10, 28), name: "Easy run", km: 6.5, daysAway: 0),
            phase: p.phase, daysToRace: p.daysToRace
        )
        let other = WorkoutNoteRequest(review: a.review, planSource: a.planSource, program: changed, recovery: a.recovery)
        let factsA = FactsBuilder.build(a)
        let factsOther = FactsBuilder.build(other)
        #expect(factsA.text != factsOther.text)
        #expect(SHA256Digest.hex(factsA.hashText) == SHA256Digest.hex(factsOther.hashText))
    }
}

@Suite("Flat series diagnostic")
struct FlatSeriesTests {
    private func analysis(_ splits: [(pace: Double, hr: Double)]) -> WorkoutAnalysis {
        WorkoutAnalysis(
            runId: "r", computedAt: .distantPast,
            dataQuality: WorkoutAnalysis.DataQuality(hasHr: true, hasRoute: false, hasDistanceSeries: true, hasCadence: false, hasPower: false),
            totals: WorkoutAnalysis.Totals(distanceKm: Double(splits.count), movingSeconds: 0, elapsedSeconds: 0, pauseCount: 0, pausedSeconds: 0),
            splits: splits.enumerated().map {
                WorkoutAnalysis.Split(index: $0.offset + 1, distanceKm: 1, movingSeconds: $0.element.pace, paceSecPerKm: $0.element.pace, avgHr: $0.element.hr)
            }
        )
    }

    @Test func fourIdenticalSplitsAreFlat() {
        #expect(analysis([(360, 158), (360, 158), (360, 158), (360, 158), (330, 150), (400, 142)]).flatSeries)
        #expect(analysis([(360.2, 157.6), (359.9, 158.4), (360, 158), (360.4, 158)]).flatSeries)
    }

    @Test func threeEqualHeartRatesAreNot() {
        #expect(!analysis([(360, 158), (360, 158), (360, 158), (360, 159)]).flatSeries)
        #expect(!analysis([(360, 158), (360, 158), (360, 158)]).flatSeries)
        #expect(!WorkoutNoteFixture.tempoAnalysis.flatSeries)
    }
}
