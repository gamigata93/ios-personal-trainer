import Foundation
import Testing
import Domain

/// The worked request: 10 km race on Sun 6 Dec 2026, plan start Mon 12 Oct,
/// 8 weeks, Mon/Wed/Fri, 18.44 km a week, longest run 17.0 km, 337 s/km.
enum WorkedRequest {
    static func make(days: Set<Weekday> = [.monday, .wednesday, .friday], notes: [String] = []) -> PlanRequest {
        PlanRequest(
            race: RaceSetup(distanceKm: 10, elevationGainM: 0, raceDate: LocalDate(year: 2026, month: 12, day: 6), trainingDays: days),
            fitness: FitnessSummary(weeklyKm: 18.44, longestRunKm: 17.0, avgPaceSecPerKm: 337),
            today: LocalDate(year: 2026, month: 10, day: 10),
            planKind: .tenK,
            source: .custom,
            revisionNotes: notes
        )
    }

    static let request = make()
}

@Suite("Prompt builders")
struct PromptBuilderTests {
    @Test func planPromptLines() {
        let lines = PlanPromptBuilder.build(WorkedRequest.request).facts
        #expect(lines == [
            "Race: 10 km on 2026-12-06 (Sun)",
            "Plan starts: 2026-10-12 (Mon)",
            "Weeks: 8",
            "Training days: Monday, Wednesday, Friday",
            "Elevation gain: 0 m",
            "Current weekly distance: 18.4 km",
            "Longest recent run: 17.0 km",
            "Average pace: 5:37 /km",
            "Phases in order: base, build, peak, taper (the last week is taper)",
            "Session types: easy, tempo, threshold, intervals, long",
            "Never plan more than 115% of the larger of the previous two weeks' distance",
            "Long run cap: 18 km",
            "Use only the training days listed",
            "No session on the race day or the day before",
        ])
    }

    @Test func noPaceLineWithoutPace() {
        let base = WorkedRequest.request
        let request = PlanRequest(
            race: base.race, fitness: FitnessSummary(weeklyKm: 0, longestRunKm: 0, avgPaceSecPerKm: nil),
            today: base.today, planKind: .tenK, source: .custom
        )
        #expect(!PlanPromptBuilder.build(request).text.contains("Average pace"))
    }

    @Test func atMostEightRevisionNotes() {
        let notes = (1...9).map { "Note \($0)" }
        let text = PlanPromptBuilder.build(WorkedRequest.make(notes: notes)).text
        #expect(text.contains("Fix these problems from your last attempt:\nNote 1\n"))
        #expect(text.hasSuffix("Note 8"))
        #expect(!text.contains("Note 9"))
        #expect(!PlanPromptBuilder.build(WorkedRequest.request).text.contains("Fix these problems"))
    }

    private let longRun = CoachNoteRequest(
        sessionName: "Long run", sessionType: .long, status: .completed, plannedKm: 10, doneKm: 7, doneDurationSeconds: 2_520,
        paceSecPerKm: 360, weekIndex: 2, weeksTotal: 8, phase: .base, daysToRace: 44,
        sleep: SleepFact(asleepMinutes: 450, deltaPercent: 7), hrv: HRVFact(valueMs: 58, deltaPercent: -6),
        restingHr: RestingHRFact(bpm: 49, deltaBpm: 0.5)
    )

    @Test func coachNoteFactLines() {
        #expect(CoachNotePromptBuilder.factLines(longRun) == [
            "Session: Long run (Long run)",
            "Plan position: week 2 of 8, base phase, 44 days to race.",
            "Planned: 10.0 km",
            "Done: 7.0 km in 42:00 (6:00 /km)",
            "Difference: \u{2212}3.0 km",
            "Sleep last night: 7h 30m (+7% vs your last 7 nights)",
            "HRV: 58 ms (\u{2212}6% vs last 7 nights)",
            "Resting heart rate: 49 bpm (About the same vs last 7 days)",
        ])
        #expect(CoachNoteRequest.sampleShortRun == longRun)
    }

    @Test func notRecordedAndMissingRecovery() {
        let request = CoachNoteRequest(sessionName: "Easy run", sessionType: .easy, status: .notRecorded, plannedKm: 5)
        #expect(CoachNotePromptBuilder.factLines(request) == ["Session: Easy run (Easy)", "Planned: 5.0 km", "Status: not recorded"])
        let missed = CoachNoteRequest(sessionName: "Easy run", sessionType: .easy, status: .missed, plannedKm: 5)
        #expect(CoachNotePromptBuilder.factLines(missed).last == "Status: marked missed")
    }

    @Test func instructionsSayTheRules() {
        let text = CoachNotePromptBuilder.instructions
        for part in ["80 words", "\"you\"", "ONLY the facts", "Never invent numbers", "no medical advice", "missing", "one concrete next step", "no emoji and no markdown"] {
            #expect(text.localizedCaseInsensitiveContains(part), "\(part)")
        }
    }
}

@Suite("Coach note validator")
struct CoachNoteValidatorTests {
    private let facts = CoachNotePromptBuilder.factLines(.sampleShortRun).joined(separator: "\n")

    private func note(_ observation: String) -> CoachNote {
        CoachNote(headline: "Long run", observation: observation, nextStep: "Rest tomorrow.")
    }

    @Test func numbersFromTheFactsAreSupported() {
        #expect(CoachNoteValidator.flags(note("You ran 7.0 of 10.0 km at a 6:00 pace in week 2."), facts: facts).isEmpty)
    }

    @Test func inventedNumbersAreFlagged() {
        #expect(CoachNoteValidator.flags(note("You ran 9.5 km."), facts: facts) == [.unsupportedNumbers(["9.5"])])
        #expect(CoachNoteFlag.unsupportedNumbers(["9.5"]).message == "Numbers not in the facts: 9.5")
    }

    @Test func lengthLimits() {
        let exactly = String(repeating: "a", count: 240)
        #expect(CoachNoteValidator.flags(note(exactly), facts: facts).isEmpty)
        let long = String(repeating: "a", count: 251)
        #expect(CoachNoteValidator.flags(note(long), facts: facts) == [.tooLong(field: "Observation", limit: 240)])
        #expect(CoachNoteFlag.tooLong(field: "Observation", limit: 240).message == "Observation longer than 240 characters")
    }
}

@Suite("Plan draft")
struct PlanDraftTests {
    private let request = WorkedRequest.request

    private func week(_ index: Int, _ phase: PlanPhase, _ sessions: [(Weekday, SessionType, Double)]) -> DraftWeek {
        DraftWeek(index: index, phase: phase, sessions: sessions.map { DraftSession(weekday: $0.0, type: $0.1, distanceKm: $0.2) })
    }

    private func eightWeeks(_ phases: [PlanPhase] = [.base, .base, .base, .build, .build, .peak, .peak, .taper]) -> [DraftWeek] {
        phases.enumerated().map { week($0.offset + 1, $0.element, [(.monday, .tempo, 5), (.wednesday, .easy, 6), (.friday, .long, 7.5)]) }
    }

    @Test func expandsWeekOneExactly() throws {
        var weeks = eightWeeks()
        weeks[3] = week(4, .build, [(.monday, .threshold, 5), (.wednesday, .easy, 6), (.friday, .long, 7.5)])
        weeks[4] = week(5, .build, [(.monday, .intervals, 7.5), (.wednesday, .easy, 6), (.friday, .long, 11)])
        let plan = PlanDraftExpander.expand(PlanDraft(weeks: weeks), request: request, generatedBy: "on-device-v1")
        #expect(plan.generatedBy == "on-device-v1")
        let first = plan.weeks[0]
        #expect(first.sessions.map(\.id) == ["2026-10-12", "2026-10-14", "2026-10-16"])
        #expect(first.targetKm == 18.5)

        let tempo = first.sessions[0]
        #expect(tempo.name == "Tempo run" && tempo.effort == "Comfortably hard" && tempo.estimatedMinutes == 30)
        #expect(tempo.segments == [
            Segment(label: "Warm-up", detail: "Easy jog", distanceKm: 1.0),
            Segment(label: "Tempo", detail: "3 km continuous, comfortably hard", distanceKm: 3.0),
            Segment(label: "Cool-down", detail: "Easy jog", distanceKm: 1.0),
        ])
        #expect(tempo.originalDate == tempo.date && !tempo.isMissed)
        let easy = first.sessions[1]
        #expect(easy.name == "Easy run" && easy.effort == "Conversational" && easy.estimatedMinutes == 35)
        #expect(easy.segments == [Segment(label: "Easy", detail: "Conversational effort", distanceKm: 6.0)])
        let long = first.sessions[2]
        #expect(long.name == "Long run" && long.effort == "Steady" && long.estimatedMinutes == 40)
        #expect(long.segments == [Segment(label: "Long run", detail: "Steady effort", distanceKm: 7.5)])

        let threshold = try #require(plan.session(id: "2026-11-02"))
        #expect(threshold.estimatedMinutes == 30)
        #expect(threshold.segments.map(\.distanceKm) == [1.0, 3.0, 1.0])
        #expect(threshold.segments[1].detail == "2 x 8 min at threshold, 90 s jog recovery")

        let intervals = try #require(plan.session(id: "2026-11-09"))
        #expect(intervals.segments.map(\.distanceKm) == [1.5, 4.5, 1.5])
        #expect(intervals.segments[1].detail == "4 x 800 m, 400 m jog")
        #expect(intervals.estimatedMinutes == 40)

        let longBuild = try #require(plan.session(id: "2026-11-13"))
        #expect(longBuild.segments == [Segment(label: "Long run", detail: "Steady, last 2 km at moderate effort", distanceKm: 11)])
        #expect(longBuild.estimatedMinutes == 60)
    }

    @Test func validatorReportsEachProblem() {
        let ok = PlanDraft(weeks: eightWeeks())
        #expect(PlanDraftValidator.violations(ok, request: request).isEmpty)
        #expect(PlanDraftValidator.violations(PlanDraft(weeks: Array(eightWeeks().prefix(7)) + []), request: request)
            .contains(.wrongWeekCount(expected: 8, got: 7)))

        var tuesday = eightWeeks()
        tuesday[0] = week(1, .base, [(.tuesday, .easy, 5)])
        #expect(PlanDraftValidator.violations(PlanDraft(weeks: tuesday), request: request) == [.weekdayNotAllowed(week: 1, weekday: .tuesday)])

        var twoMondays = eightWeeks()
        twoMondays[0] = week(1, .base, [(.monday, .easy, 5), (.monday, .tempo, 5)])
        #expect(PlanDraftValidator.violations(PlanDraft(weeks: twoMondays), request: request) == [.duplicateWeekday(week: 1, weekday: .monday)])

        var zero = eightWeeks()
        zero[0] = week(1, .base, [(.monday, .easy, 0)])
        #expect(PlanDraftValidator.violations(PlanDraft(weeks: zero), request: request) == [.nonPositiveDistance(week: 1)])

        let backwards = PlanDraft(weeks: eightWeeks([.base, .peak, .build, .build, .build, .peak, .peak, .taper]))
        #expect(PlanDraftValidator.violations(backwards, request: request) == [.phaseOrder(week: 3)])

        let noTaper = PlanDraft(weeks: eightWeeks([.base, .base, .base, .build, .build, .peak, .peak, .peak]))
        #expect(PlanDraftValidator.violations(noTaper, request: request) == [.lastWeekNotTaper])

        var shuffled = eightWeeks()
        shuffled.swapAt(1, 2)
        #expect(PlanDraftValidator.violations(PlanDraft(weeks: shuffled), request: request).contains(.weekIndexOrder))

        let empty = PlanDraft(weeks: eightWeeks().map { DraftWeek(index: $0.index, phase: $0.phase, sessions: []) })
        #expect(PlanDraftValidator.violations(empty, request: request) == [.noSessions])
        #expect(DraftViolation.wrongWeekCount(expected: 8, got: 7).message == "The plan needs exactly 8 weeks, not 7.")
    }

    @Test func planValidatorRejectsARaceDaySessionAfterExpansion() {
        let request = WorkedRequest.make(days: [.monday, .sunday])
        var weeks = (1...8).map { week($0, $0 == 8 ? .taper : .base, [(.monday, .easy, 4)]) }
        weeks[7] = week(8, .taper, [(.monday, .easy, 4), (.sunday, .easy, 3)])
        let draft = PlanDraft(weeks: weeks)
        #expect(PlanDraftValidator.violations(draft, request: request).isEmpty)
        let plan = PlanDraftExpander.expand(draft, request: request, generatedBy: "on-device-v1")
        let raceDay = LocalDate(year: 2026, month: 12, day: 6)
        #expect(plan.session(on: raceDay) != nil)
        #expect(PlanValidator.violations(plan, request: request).contains(.sessionOutsideWindow(raceDay)))
    }
}

@Suite("Model choice and availability")
struct ModelChoiceTests {
    @Test func idsAndTags() {
        #expect(ModelChoice.apple.map(\.id) == ["onDevice", "pcc.light", "pcc.moderate", "pcc.deep"])
        #expect(ModelChoice.apple.map(\.generatedBy) == ["on-device-v1", "pcc-light-v1", "pcc-moderate-v1", "pcc-deep-v1"])
        #expect(ModelChoice(id: "pcc.moderate") == .privateCloud(reasoning: .moderate))
        #expect(ModelChoice(id: "anthropic") == nil)
    }

    @Test func messages() {
        #expect(ModelAvailability.notEnabledForBuild.message
            == "Private Cloud Compute isn't enabled for this build. Request access at developer.apple.com/private-cloud-compute.")
        #expect(ModelAvailability.available.chipText == "Available")
        #expect(ModelAvailability.notReady.chipText == "Not ready")
        #expect(LLMUsage(inputTokens: 812, cachedInputTokens: 0, outputTokens: 140, reasoningTokens: 96, latencyMs: 3_240).line
            == "in 812 · out 140 · reasoning 96 · cached 0")
        #expect(LLMUsage(inputTokens: 812, outputTokens: 140, latencyMs: 3_240).line == "in 812 · out 140")
        #expect(LLMUsage(latencyMs: 3_240).latencyText == "3.2 s")
    }
}
