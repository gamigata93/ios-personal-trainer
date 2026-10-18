import Foundation
import Testing
@testable import Domain

private typealias F = EditPlanFixture

@Suite("Strength library and content")
struct StrengthContentTests {
    @Test func everyFocusHasTwoFixedListsOfFive() {
        for focus in StrengthFocus.allCases {
            let a = StrengthLibrary.exercises(focus, .a)
            let b = StrengthLibrary.exercises(focus, .b)
            #expect(a.count == 5 && b.count == 5)
            #expect(a.map(\.name) != b.map(\.name))
            // Nothing random: the same call gives the same list.
            #expect(StrengthLibrary.exercises(focus, .a) == a)
        }
    }

    @Test func dosesFollowThePhase() throws {
        func goblet(_ phase: PlanPhase) throws -> StrengthExercise {
            try #require(StrengthContentBuilder.session(date: F.day(10, 14), focus: .lowerBody, minutes: 30, phase: phase, variant: .a).exercises.first)
        }
        #expect(try goblet(.base).doseText == "2 \u{00D7} 12")
        #expect(try goblet(.build).doseText == "3 \u{00D7} 10")
        #expect(try goblet(.peak).doseText == "3 \u{00D7} 6")
        #expect(try goblet(.taper).doseText == "2 \u{00D7} 6")
        let build = StrengthContentBuilder.session(date: F.day(10, 14), focus: .lowerBody, minutes: 30, phase: .build, variant: .a)
        #expect(build.exercises.map(\.doseText) == ["3 \u{00D7} 10", "3 \u{00D7} 10", "3 \u{00D7} 10 per side", "3 \u{00D7} 10", "3 \u{00D7} 40 s per side"])
        #expect(build.effort == "Moderate weight, 2 reps in reserve")
        #expect(build.name == "Strength: Lower body A")
        #expect(build.id == "strength-2026-10-14")
        // Mobility keeps its own dose in every phase.
        let mobility = StrengthContentBuilder.session(date: F.day(10, 14), focus: .mobility, minutes: 20, phase: .peak, variant: .a)
        #expect(mobility.exercises.first?.doseText == "2 \u{00D7} 45 s per side")
        #expect(mobility.effort == "Easy range of motion, never into pain")
    }

    @Test func variantsAlternatePerFocusInDateOrder() {
        let items: [(date: LocalDate, focus: StrengthFocus)] = [
            (F.day(10, 21), .lowerBody), (F.day(10, 14), .lowerBody), (F.day(10, 16), .core), (F.day(10, 28), .lowerBody),
        ]
        let variants = StrengthContentBuilder.variants(for: items)
        #expect(variants[F.day(10, 14)] == .a && variants[F.day(10, 21)] == .b && variants[F.day(10, 28)] == .a)
        #expect(variants[F.day(10, 16)] == .a)
        // Mid-plan: one lower body session came before.
        #expect(StrengthContentBuilder.variants(for: [(F.day(11, 4), .lowerBody)], earlier: [.lowerBody: 1])[F.day(11, 4)] == .b)
    }
}

@Suite("Strength placement and validation")
struct StrengthPlacementTests {
    private let runs: [LocalDate: SessionType] = [
        F.day(10, 12): .tempo, F.day(10, 14): .easy, F.day(10, 16): .long,
    ]

    private func problems(_ date: LocalDate) -> [StrengthPlacement.Problem] {
        StrengthPlacement.problems(
            date: date, runs: runs, trainingDays: [.monday, .tuesday, .wednesday, .thursday, .friday], raceDate: F.raceDay, planStart: F.planStart
        )
    }

    @Test func rules() {
        #expect(problems(F.day(10, 14)).isEmpty)
        #expect(problems(F.day(10, 13)).isEmpty)
        #expect(problems(F.day(10, 12)) == [.onHardRunDay])
        #expect(problems(F.day(10, 15)) == [.dayBeforeLongRun])
        #expect(problems(F.day(10, 16)) == [.onHardRunDay])
        #expect(problems(F.day(10, 17)) == [.notATrainingDay])
        // Race week: Mon 30 Nov to Sun 6 Dec.
        #expect(problems(F.day(11, 30)) == [.inRaceWeek])
        #expect(problems(F.day(10, 9)) == [.outsideWindow])
        #expect(StrengthPlacement.isInRaceWeek(F.day(11, 29), raceDate: F.raceDay) == false)
    }

    @Test func draftChecksAndExpansion() throws {
        let request = PlanRequest(
            race: F.base.race, fitness: FitnessSummary(weeklyKm: 20, longestRunKm: 10, avgPaceSecPerKm: 360), today: F.day(10, 10),
            planKind: .tenK, source: .custom
        )
        let weeks = (1...8).map { index in
            DraftWeek(
                index: index, phase: index == 8 ? .taper : .base,
                sessions: [
                    DraftSession(weekday: .monday, type: .tempo, distanceKm: 5),
                    DraftSession(weekday: .wednesday, type: .easy, distanceKm: 6),
                    DraftSession(weekday: .friday, type: .long, distanceKm: 8),
                ],
                strength: index == 1
                    ? [DraftStrength(weekday: .wednesday, focus: .core, minutes: 25)]
                    : (index == 2 ? [DraftStrength(weekday: .monday, focus: .core, minutes: 10)] : [])
            )
        }
        let draft = PlanDraft(weeks: weeks)
        let violations = PlanDraftValidator.violations(draft, request: request)
        #expect(violations == [.strengthMinutes(week: 2), .strengthPlacement(week: 2, weekday: .monday, .onHardRunDay)])
        #expect(DraftViolation.strengthPlacement(week: 2, weekday: .monday, .onHardRunDay).message
            == "Week 2 has strength on Monday, the same day as a tempo, threshold, interval or long run.")

        let good = PlanDraft(weeks: weeks.map { week in
            DraftWeek(index: week.index, phase: week.phase, sessions: week.sessions, strength: week.index == 2 ? [] : week.strength)
        })
        #expect(PlanDraftValidator.violations(good, request: request).isEmpty)
        let plan = PlanDraftExpander.expand(good, request: request, generatedBy: "test")
        let strength = try #require(plan.strengthSessions.first)
        #expect(plan.strengthSessions.count == 1)
        #expect(strength.date == F.day(10, 14) && strength.focus == .core && strength.minutes == 25 && strength.variant == .a)
        #expect(plan.weeks[0].strength.count == 1)
        #expect(PlanValidator.strengthViolations(plan).isEmpty)
    }
}

@Suite("Strength completion and adherence")
struct StrengthCompletionTests {
    private func workout(_ day: Int, minutes: Double, id: String) -> CompletedStrength {
        CompletedStrength(id: id, localDate: F.day(10, day), durationSeconds: minutes * 60, kind: .traditionalStrength)
    }

    private var plan: TrainingPlan {
        let strength = [14, 21, 28].map { StrengthContentBuilder.session(date: F.day(10, $0), focus: .core, minutes: 30, phase: .base, variant: .a) }
        return F.base.replacing(sessions: F.base.sessions, strength: strength)
    }

    @Test func sameDayFifteenMinutesLongestWins() {
        let matches = StrengthCompletionMatcher.match(
            sessions: plan.strengthSessions,
            workouts: [workout(14, minutes: 20, id: "a"), workout(14, minutes: 35, id: "b"), workout(21, minutes: 14, id: "c"), workout(22, minutes: 40, id: "d")]
        )
        #expect(matches["strength-2026-10-14"]?.id == "b")
        #expect(matches["strength-2026-10-21"] == nil)
        #expect(matches.count == 1)
        #expect(StrengthCompletionMatcher.match(sessions: plan.strengthSessions, workouts: [workout(21, minutes: 15, id: "e")]).count == 1)
    }

    @Test func adherenceCountsStrength() {
        let progress = PlanProgress(plan: plan, runs: F.runs, strength: [workout(14, minutes: 30, id: "a")], today: F.day(10, 28))
        // Runs: 7 due (12 to 26 Oct), 6 done. Strength: 14 and 21 due, 14 done; 28 is today and not done.
        #expect(progress.dueCount == 9)
        #expect(progress.completedCount == 7)
        #expect(progress.status(of: plan.strengthSessions[1]) == .notRecorded)
        #expect(progress.status(of: plan.strengthSessions[2]) == .today)
    }
}

@Suite("Feedback")
struct FeedbackTests {
    private func feedback(
        _ id: String, day: Int, _ reports: [AreaReport], status: WorkoutFeedback.Status = .reported, note: String? = nil
    ) -> WorkoutFeedback {
        WorkoutFeedback(
            workoutId: id, workoutKind: .run, localDate: F.day(10, day), status: status, areas: reports, note: note,
            recordedAt: Date(timeIntervalSince1970: Double(day))
        )
    }

    @Test func lines() {
        let knee = AreaReport(area: .knee, side: .left, kind: .pain, level: .moderate)
        let calves = AreaReport(area: .calf, side: .both, kind: .ache, level: .mild)
        let back = AreaReport(area: .lowerBack, side: .both, kind: .ache, level: .severe)
        let other = AreaReport(area: .other, otherName: "Elbow\nleft", side: .right, kind: .ache, level: .mild)
        #expect(feedback("a", day: 26, [knee, calves], note: "Tight after\nthe hills").line
            == "Mon 26 Oct run: pain, left knee, moderate; ache, both calves, mild. Note: Tight after the hills")
        #expect(feedback("b", day: 26, [back]).line == "Mon 26 Oct run: ache, lower back, severe.")
        #expect(feedback("c", day: 26, [other]).line == "Mon 26 Oct run: ache, right Elbow left, mild.")
        #expect(feedback("d", day: 26, [], status: .noIssues).line == "Mon 26 Oct run: no issues.")
        #expect(feedback("e", day: 26, [], status: .skipped).line == nil)
        // Reported without areas is no issues; the note is cut to 200 characters.
        #expect(feedback("f", day: 26, []).status == .noIssues)
        #expect(feedback("g", day: 26, [], status: .noIssues, note: String(repeating: "x", count: 250)).note?.count == 200)
    }

    @Test func triggers() {
        let mildPain = feedback("a", day: 26, [AreaReport(area: .shin, side: .left, kind: .pain, level: .mild)])
        #expect(FeedbackRules.trigger(mildPain, history: [])?.reason == .pain)
        let severeAche = feedback("b", day: 26, [AreaReport(area: .calf, side: .left, kind: .ache, level: .severe)])
        #expect(FeedbackRules.trigger(severeAche, history: [])?.reason == .severeAche)
        let moderate = feedback("c", day: 26, [AreaReport(area: .calf, side: .left, kind: .ache, level: .moderate)])
        #expect(FeedbackRules.trigger(moderate, history: []) == nil)
        // The same area (any side) moderately within 7 days: 6 days back counts, 7 does not.
        let sixBack = feedback("d", day: 20, [AreaReport(area: .calf, side: .right, kind: .ache, level: .moderate)])
        let sevenBack = feedback("e", day: 19, [AreaReport(area: .calf, side: .left, kind: .ache, level: .severe)])
        #expect(FeedbackRules.trigger(moderate, history: [sixBack])?.reason == .repeatedAche)
        #expect(FeedbackRules.trigger(moderate, history: [sevenBack]) == nil)
        let otherArea = feedback("f", day: 24, [AreaReport(area: .knee, side: .left, kind: .ache, level: .moderate)])
        #expect(FeedbackRules.trigger(moderate, history: [otherArea]) == nil)
        let mild = feedback("g", day: 24, [AreaReport(area: .calf, side: .left, kind: .ache, level: .mild)])
        #expect(FeedbackRules.trigger(moderate, history: [mild]) == nil)
        #expect(FeedbackRules.trigger(feedback("h", day: 26, [], status: .skipped), history: []) == nil)
        // The strongest pain is the one reported.
        let two = feedback("i", day: 26, [
            AreaReport(area: .shin, side: .left, kind: .pain, level: .mild), AreaReport(area: .knee, side: .right, kind: .pain, level: .severe),
        ])
        #expect(FeedbackRules.trigger(two, history: [])?.report.area == .knee)
    }

    @Test func modelLinesAreRecentNewestFirst() {
        let items = (10...27).map { feedback("w\($0)", day: $0, [], status: .noIssues) } + [feedback("s", day: 27, [], status: .skipped)]
        let lines = FeedbackRules.lines(items, today: F.day(10, 28))
        #expect(lines.count == 8)
        #expect(lines.first == "Tue 27 Oct run: no issues.")
        #expect(lines.last == "Tue 20 Oct run: no issues.")
    }
}

@Suite("Plan adjustment")
struct PlanAdjustmentTests {
    /// Fixture plan with strength on Wed 28 Oct (lower body) and Wed 4 Nov (core).
    private var plan: TrainingPlan {
        let strength = [
            StrengthContentBuilder.session(date: F.day(10, 21), focus: .lowerBody, minutes: 30, phase: .base, variant: .a),
            StrengthContentBuilder.session(date: F.day(10, 28), focus: .lowerBody, minutes: 30, phase: .base, variant: .b),
            StrengthContentBuilder.session(date: F.day(11, 4), focus: .core, minutes: 25, phase: .build, variant: .a),
        ]
        return F.base.replacing(sessions: F.base.sessions, strength: strength)
    }

    private func trigger(_ area: BodyArea = .knee, kind: DiscomfortKind = .pain, level: DiscomfortLevel = .moderate) -> AdjustmentTrigger {
        let report = AreaReport(area: area, side: .left, kind: kind, level: level)
        let feedback = WorkoutFeedback(workoutId: "w", workoutKind: .run, localDate: F.day(10, 26), status: .reported, areas: [report], recordedAt: .distantPast)
        return FeedbackRules.trigger(feedback, history: []) ?? AdjustmentTrigger(feedback: feedback, report: report, reason: .pain)
    }

    @Test func window() throws {
        // Wed 28 Oct, nothing done today: today to Sun 8 Nov.
        let open = try #require(AdjustmentWindow.make(progress: PlanProgress(plan: plan, runs: F.runs, today: F.day(10, 28))))
        #expect(open.start == F.day(10, 28) && open.end == F.day(11, 8))
        // Today's run done: from tomorrow.
        let done = try #require(AdjustmentWindow.make(progress: PlanProgress(plan: plan, runs: F.runs + [F.run(F.day(10, 28), 7)], today: F.day(10, 28))))
        #expect(done.start == F.day(10, 29))
        // Near the race: never past 2 days before race day.
        let late = try #require(AdjustmentWindow.make(progress: PlanProgress(plan: plan, runs: [], today: F.day(11, 30))))
        #expect(late.end == F.day(12, 4))
        #expect(AdjustmentWindow.make(progress: PlanProgress(plan: plan, runs: [], today: F.day(12, 5))) == nil)
    }

    @Test func ruleBasedChange() throws {
        let window = AdjustmentWindow(start: F.day(10, 28), end: F.day(11, 8))
        let draft = RuleBasedAdjustment.draft(plan: plan, window: window, trigger: trigger())
        // 28 Oct easy 6.5 -> 5.0, 30 Oct long 10 -> easy 8.0, 2 Nov threshold 5 -> easy 4.0, 4 Nov 6 -> 5.0, 6 Nov 7 -> 5.5.
        #expect(draft.runs.map(\.distanceKm) == [5.0, 8.0, 4.0, 5.0, 5.5])
        #expect(draft.runs.allSatisfy { $0.type == .easy })
        // Knee: lower body becomes mobility, core stays.
        #expect(draft.strength.map(\.focus) == [.mobility, .core])
        #expect(draft.strength.map(\.minutes) == [20, 25])
        #expect(draft.reason == "Because of the pain, left knee, moderate, runs are easy and 20% shorter until Sun 8 Nov.")
        #expect(AdjustmentValidator.violations(draft, plan: plan, window: window).isEmpty)

        let severe = RuleBasedAdjustment.draft(plan: plan, window: window, trigger: trigger(level: .severe))
        #expect(severe.runs.first?.date == F.day(10, 30))
        #expect(severe.reason.hasPrefix("Because of the pain, left knee, severe, no running for 2 days"))
        let back = RuleBasedAdjustment.draft(plan: plan, window: window, trigger: trigger(.lowerBack))
        #expect(back.strength.map(\.focus) == [.mobility, .mobility])
    }

    @Test func validator() {
        let window = AdjustmentWindow(start: F.day(10, 28), end: F.day(11, 8))
        let more = AdjustmentDraft(runs: [AdjustmentDraft.Run(date: F.day(10, 30), type: .long, distanceKm: 40)], strength: [], reason: "More.")
        let violations = AdjustmentValidator.violations(more, plan: plan, window: window)
        #expect(violations.contains(.moreRunning(newKm: 40, currentKm: 34.5)))
        #expect(violations.contains(.longRunOverCap(F.day(10, 30))))
        let outside = AdjustmentDraft(
            runs: [
                AdjustmentDraft.Run(date: F.day(11, 9), type: .easy, distanceKm: 3), AdjustmentDraft.Run(date: F.day(10, 29), type: .easy, distanceKm: 3),
                AdjustmentDraft.Run(date: F.day(11, 2), type: .threshold, distanceKm: 5),
            ],
            strength: [AdjustmentDraft.Strength(date: F.day(11, 2), focus: .core, minutes: 20)],
            reason: String(repeating: "x", count: 161)
        )
        #expect(AdjustmentValidator.violations(outside, plan: plan, window: window) == [
            .outsideWindow(F.day(11, 9)), .notATrainingDay(F.day(10, 29)), .strength(F.day(11, 2), .onHardRunDay), .reason,
        ])
        #expect(AdjustmentViolation.moreRunning(newKm: 40, currentKm: 34.5).message == "The new schedule runs 40.0 km, more than the current 34.5 km.")
    }

    @Test func builderAndApply() throws {
        let window = AdjustmentWindow(start: F.day(10, 28), end: F.day(11, 8))
        let draft = RuleBasedAdjustment.draft(plan: plan, window: window, trigger: trigger())
        let change = AdjustmentBuilder.make(draft, plan: plan, window: window, triggerLine: "pain, left knee, moderate", writtenBy: "rules")
        #expect(change.beforeRuns.map(\.id) == ["2026-10-28", "2026-10-30", "2026-11-02", "2026-11-04", "2026-11-06"])
        #expect(change.afterRuns.map(\.id) == change.beforeRuns.map(\.id))
        #expect(change.afterRuns.map(\.name) == ["Easy run", "Easy run", "Easy run", "Easy run", "Easy run"])
        // Mobility continues the plan's alternation (no mobility before), core keeps its A.
        #expect(change.afterStrength.map(\.name) == ["Strength: Mobility A", "Strength: Core A"])
        #expect(change.changes.first?.line == "Wed 28 Oct: Easy run 6.5 km + Strength: Lower body B \u{2192} Easy run 5.0 km + Strength: Mobility A")
        #expect(change.changes.count == 5)
        let applied = change.applied(to: plan)
        #expect(applied.session(on: F.day(10, 30))?.type == .easy)
        #expect(applied.session(on: F.day(10, 26))?.type == .tempo)
        #expect(applied.strengthSession(on: F.day(10, 21))?.focus == .lowerBody)
        #expect(applied.sessions.count == plan.sessions.count)
        // A run the plan already holds elsewhere keeps the new one's id unique.
        let moved = try #require(PlanEditApplier.apply(.move(sessionId: F.id(10, 28), from: F.day(10, 28), to: F.day(10, 27)), to: plan))
        let extra = AdjustmentDraft(runs: [AdjustmentDraft.Run(date: F.day(10, 28), type: .easy, distanceKm: 3)], strength: [], reason: "x")
        let later = AdjustmentWindow(start: F.day(10, 28), end: F.day(10, 28))
        #expect(AdjustmentBuilder.make(extra, plan: moved, window: later, triggerLine: "", writtenBy: "").afterRuns.first?.id == "2026-10-28-a")
    }

    @Test func prompt() {
        let window = AdjustmentWindow(start: F.day(10, 28), end: F.day(11, 1))
        let prompt = AdjustmentPromptBuilder.build(plan: plan, window: window, trigger: trigger(), feedbackLines: ["Mon 26 Oct run: pain, left knee, moderate."])
        #expect(prompt.facts.contains("Days you may change: 2026-10-28 (Wed) to 2026-11-01 (Sun)"))
        #expect(prompt.facts.contains("2026-10-28 (Wed, base): easy run 6.5 km; strength lower body 30 min"))
        #expect(prompt.facts.contains("2026-10-29 (Thu, base): rest"))
        #expect(prompt.facts.contains("Current running total: 16.5 km (never more)"))
        #expect(prompt.facts.first == "Trigger: Mon 26 Oct run: pain, left knee, moderate.")
        #expect(prompt.instructions.contains("Never add running"))
        #expect(AdjustmentPromptBuilder.build(plan: plan, window: window, trigger: trigger(), feedbackLines: [], revisionNotes: ["a"]).text
            .hasSuffix("\n\nFix these problems:\na"))
    }
}
