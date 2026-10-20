---
name: ios-trainer-app
description: Product rules, Clean Architecture layering (via Swift Package targets), SOLID checklist and design tokens for the on-device AI trainer iOS app. All workout data comes from HealthKit; there is no file import.
---

# Personal AI trainer: iOS app (Swift, on-device)

Everything runs on the phone. The app reads workouts and recovery data from
HealthKit, stores them in a local database, and calls an LLM to write coach
notes, build the plan and run the morning check. There is no backend server.
Apply these rules to every change without being asked.

Project setup: Xcode project created with Storage: None and Testing: Swift
Testing with XCTest UI Tests. The user has an Apple Watch. Delete the
template's sample code (placeholder ContentView content, example tests, any
sample model) as part of the first task.

## Scope: what is in and out
In: HealthKit read access, local database, LLM coach, plan generation, calendar,
onboarding with a fitness baseline.
The app plans races from 5 km up to a full marathon (AppScope: 5.0 to 42.2 km, 42.195 as the label).
Only creation is restricted (Race setup and CreatePlan, error RaceOutOfScope); existing plans keep working.
Out (do not build or reference): any FIT, GPX or TCX file import; code specific
to any one workout app (WorkOutdoors etc.); a server or API of our own; HealthKit
writes (read-only); Android; push notifications (the morning check shows on app open).

## HealthKit rules
- Read ALL workouts from Health, whichever app wrote them (Apple Watch Workout
  app, WorkOutdoors, others). Never filter by source. Keep the source app name as
  a label only.
- Workout richness varies by source. Route, heart rate and extras may be
  missing. Domain code must accept partial data and mark what is unknown.
- Summaries depend on activity type. Pace, splits and elevation apply to running,
  hiking and cycling. Strength, yoga etc. get duration, heart rate and energy only.
- Dedupe by the HealthKit workout UUID. Flag overlapping workouts of the same
  type so the richer one can be kept.
- Request every needed read type up front: workouts, workout routes, heart rate,
  resting heart rate, VO2 max, sleep, HRV, plus date of birth and biological sex.
  HealthReadSet (Infrastructure) is the single list: also active energy, walking/running distance,
  step count (cadence is derived from it), running power, workout effort score and estimated
  workout effort score. Adding a type makes existing installs see Connect Health once more.
- Read permission is hidden by design: an empty result can mean no data OR no
  access. Model three outcomes: available, locked (retry after unlock), and
  empty-or-not-allowed. Never crash on any of them. Show "data as of <time>".
- HealthKit reads fail while the phone is locked. Treat that as normal.
- The Info.plist needs the HealthKit usage descriptions or the app crashes when
  asking for permission. Re-check authorization on each launch.
- Sleep is read (sleep analysis, every source). inBed samples are ignored (Apple
  devices stopped writing them on iOS 18); sessions are split at gaps over 60 minutes.
  A night is assigned to the wake-up date. One source per night (most sleep, ties to
  Apple Watch), never summed across sources. Core, Deep and REM are shown as estimates.
- Sleep rules (SleepRules.swift): naps (< 90 min asleep, woke 09:00 to 20:00) and nights
  under 120 minutes asleep are ignored; the comparison uses the 7 previous nights, needs
  at least 3, and has a +/-3% neutral band. The cache keeps nightly summaries only.
- HRV is SDNN only and never mixed with RMSSD. Nightly HRV is the mean of the samples inside
  the night's sleep window (fallback window 00:00 to 08:00 local when there is no sleep night),
  needing at least 2 samples. Resting heart rate is Apple's daily daytime estimate (the latest
  sample on each local date). One source per night or day, never combined. Constants live in
  RecoveryRules.swift; the cache keeps summaries only.

## Product flow
No app-level login. The device passcode protects the app. If a lock is ever
wanted, add it as an optional Face ID lock behind an AppLock port, not a custom password.

Onboarding (shown only when no plan exists): Connect Apple Health (first launch
only) -> Starting point (loads in the background) -> Race setup -> Generating.
1. Connect Apple Health (first launch only): explain what is read, then ask for
   read access to every type in one request. Whatever the answer, continue.
2. Starting point dashboard (loads in the background):
   - VO2 max on a bell-curve scale, resting heart rate on a five-band scale, both
     placed against people of the user's age and sex. Right is always better, so
     heart rate is inverted. State that VO2 max is Apple's estimate.
   - Average heart rate during runs as a plain stat.
   - Recent PRs (5K, 10K, half marathon) found from workouts, newest tagged.
   - Suggested plans: 5K, 10K, half marathon, marathon, each with a fit label
     (Best fit, Great fit, Stretch, Later) and one-line reason, chosen by
     deterministic rules in Domain, not by the LLM.
   - Primary button continues with the selected plan (race setup prefilled with its
     distance and a suggested date). Secondary "Custom race" opens a blank setup.
3. Race setup: race day, distance (km), elevation gain (m), and which weekdays
   the user can train. No default training days: nothing is preselected or
   restored, and the user picks at least 2 and at most 6. A suggested plan
   prefills its distance and race day; "Custom race" starts blank. The distance has chips 5K, 10K,
   Half (21.1) and Marathon (42.2) that fill the field (the chip within 0.05 km is selected), a helper
   line "From 5 km up to a full marathon (42.195 km).", and locale-safe parsing (RaceDistanceParser: "."
   and "," both work). Blank reads "Enter a race distance."; outside the range "Pick a race distance from
   5 km up to a full marathon (42.195 km)." A non-medical note sits under Build my plan.
4. Generating: plan generation goes through the PlanGenerator port. The default is Automatic:
   Private Cloud Compute (light), then on-device, each with 2 validated attempts, then
   TemplatePlanGenerator (generatedBy "template-v2", with strength). Then the app opens Home.

Launch routing: never-requested -> Connect Health; no plan -> Starting point; plan -> Home.
Health reads run in the background on every launch. Screens render the cached snapshot
first, then update section by section.

Main app (floating tab bar: Home, Calendar):
- Home v1 (built): header (date, greeting, neutral pulse icon, no name), plan card
  (adherence ring, days to go, phase pill, "Week n of N"), week strip with week
  arrows and session-type icons, selected-day card (session, rest or race day),
  up next, pull to refresh. Before the start the pill reads "Starts <date>"; race
  day shows "Race day"; after the race "Finished" and no strip.
- Home v1 also has the Recovery section with the Sleep card (full width for now:
  duration, sleep window, delta vs the last 7 nights, stage bar and legend). Delta
  colors are green (up), red (down) and gray (about the same); rating colors still
  do not exist. Runs and sleep refresh in parallel and fail independently.
- Recovery also has compact HRV and Resting HR cards (2-up under the full-width Sleep
  card). Comparisons use the 7 days before (HRV in percent with a 5% neutral band, resting
  HR in bpm with a 2 bpm band, lower is better). The status colors mark better and worse
  outcomes, never a rating. Sleep and resting HR refresh in parallel; HRV starts when
  sleep finishes (it uses the sleep windows); each metric fails on its own.
- The locked notice for Recovery is one section-level line.
- Home later: last workout card (map, time, distance, Full breakdown button), morning-insight strip
  when today's session was adjusted.
- Home and Calendar read the plan only through ActivePlanStore (PlanRepository behind it), and
  completion only through CompletedRunsStore (CompletedRunsCache and RefreshCompletedRuns behind
  it: running workouts from planStart to min(today, race day), placed on local days with the
  injected calendar).
- Today's session: stats, elevation profile, structure, coach note, and the
  original session struck through with the reason when it was adjusted.
- Last workout breakdown: plan match, planned vs done, pace per km against the
  prescribed band, heart rate zones, full coach note and a next-time line.
- Calendar (built): month grid (plan months only, Monday first) with type icons,
  month arrows, the shared day card for the selected day and a legend of the type icons.
  Days before the plan or after the race are dimmed and cannot be selected. Statuses are
  completed, missed, not recorded, today and upcoming, from the same matcher as Home.
- Edit flow (Calendar only, never from Home): under the day card, one action row per available
  action (Move to next day, Move to another day… / Move forward to another day…, Swap with
  another session…, Mark as missed), each with a hint; disabled rows are dimmed. Moving or
  swapping shows a banner with Cancel; valid targets get an accent border and fill, everything
  else dims and ignores taps; month arrows keep the mode; leaving the screen cancels it.
  A saved edit selects the target day and shows a notice with Undo (plus an amber heads-up for
  back-to-back hard days); a failed edit shows "Couldn't apply that change. Your plan is
  unchanged." with Dismiss. Missed shows as a "Missed" chip and a struck gray icon (cells,
  week strip, card, detail); a moved session shows "Moved from <date>" on the card and detail.
- Session detail (built, read-only; a missed session reads "Marked as missed"): type and status chips, week and phase, distance, est. time
  and effort tiles, the matched run (distance, time, pace, delta vs plan) or, when not recorded,
  the 60% rule in plain words ("We look for a run of at least 3.0 km on the same day."),
  the structure and the session's note. No elevation profile or "adjusted" card yet.
- Completed sessions (Session detail): a neutral verdict chip (On track, Worth watching, Off plan), result
  tiles (distance, moving time, avg pace, avg HR with zone, elevation, cadence), the "Coach's note" card
  (How it went, Versus the plan, The program, Next; "Written by ..." and the fallback reason), the splits
  chart (bars by speed, planned blocks under it), heart-rate zones (blue ramp, target bracketed), plan vs
  actual per planned block, and a data footnote. Sections without data are hidden. Notes compare blocks and
  report program status. Home shows a "Latest coach note" card under Up next.
- Coach notes are written automatically only while the app is open, for completed sessions of the last
  7 days, at most 3 per refresh (newest first), and on opening such a session; older sessions get a
  "Write coach note" button. One generation at a time. Locked Health waits for the next refresh.
- After-workout feedback: on app open, each new run or strength workout from Health of the last 3 days
  (no stored answer yet) gets a popup, newest first: "Anything bothering you?" No / Yes; per area (knee, calf,
  shin, Achilles or ankle, foot, hip, hamstring, quad, lower back, other) the side, ache or pain, and level
  1-3; an optional note (200 characters). Skip stores a skip, so nothing is asked twice. Answers live in
  GRDB (workout_feedback) and are editable from Session detail ("Your feedback"). Auto coach notes wait for
  the popup, and the note's facts carry the answer. Rules (FeedbackRules): any pain, a severe ache, or a
  moderate ache in the same area twice within 7 days suggests a plan change.
- Suggested change (Home card): the next days (today, or tomorrow when today is done, to the end of next
  week) are re-drafted by Apple's models (PCC, then on-device, 2 validated attempts each) or else by
  RuleBasedAdjustment (hard runs easy, 20% shorter, leg or back strength becomes mobility, severe pain drops
  2 days of running). A change never adds running. Apply / Keep plan; Apply shows Undo. Severe pain adds
  one line: "If sharp pain lasts, check with a professional." No other medical advice. Stored in
  plan_adjustment; apply and undo check the window is unchanged.
- Navigation: two tabs (Home, Calendar) in one NavigationStack. Session detail is pushed over
  either tab from the day card's arrow or Home's Up next card, and the tab bar is hidden there.
  Strength sessions open the strength detail (exercises, dose, equipment, how-to) from the strength row.
- ActivePlanStore and CompletedRunsStore are the single shared state for plan and completion.
  Views never call repositories, caches or HealthKit directly.

## Plan rules
- Session types: easy, tempo, threshold, intervals, long (rest = no session).
  The icon shape encodes the type. Color encodes status only.
- Strength sessions are a separate list per week (id "strength-<original date>", at most one a day, 0 to 3 a
  week; the model decides how many). Only on training days, alone or on an easy-run day; never on a tempo,
  threshold, interval or long-run day, the day before a long run, or in race week (StrengthPlacement).
  The model (or template) picks a focus (lower body, calves and feet, core, full body, mobility) and minutes
  (15-60); code fills the exercises from StrengthLibrary: two fixed lists per focus (A and B, alternating
  in date order per focus), doses by phase (StrengthRules; nothing random). The template plans 2 a week in
  base and build, 1 in peak and taper, none in race week. A Health strength, functional strength, core or
  HIIT workout of at least 15 minutes on the same day completes it. Strength shows as a dumbbell (a badge on
  days with a run) in the strip and calendar, and a strength row under the day card. Edits do not move
  strength sessions.
- Statuses now: completed, missed (the user's acknowledgement, stored as a flag), not
  recorded (a past session with no matching run), today, upcoming. Precedence: completed >
  missed > notRecorded > today > upcoming (a missed session that later gets a matching run is
  completed). Ratings (green, amber, red) come later; completed is drawn in #7C9CFF with a check badge, and a
  rating will later recolor only the icon.
- Completion: a run on the same local day covering at least 60% of the planned
  distance (PlanProgressRules.matchShare, exactly 60% counts) completes the session;
  the longest candidate wins, a run matches one session at most, and runs on days
  without a session are ignored. Adherence = completed / due (runs and strength sessions), where due = sessions
  before today plus today's once completed or missed; a missed session is due and not
  completed; nothing due shows "-", never 0%. Up next skips missed sessions.
- Edits change dates or the missed flag only, never content. The one exception is an applied suggested
  change, which replaces the runs and strength sessions in its window (logged in plan_adjustment, with Undo). A session's `id` is its ORIGINAL
  date and never changes; placement uses `date`, identity and routes use `id`. The plan is
  returned with each session in the week of its current date (weeks keep their phase and target).
- Allowed targets (PlanEditRules.swift): free days from max(today, planStart) to raceDate minus
  2 days (race day and the day before never), any weekday. A target must have no session.
- Move: any session that is not completed (not recorded, missed, today, upcoming); a move clears
  missed. "Move to next day" is offered for today or upcoming sessions only.
- Swap: only between two different sessions that are both today or upcoming.
- Missed: only for not-recorded or today's sessions.
- Every plan change is logged with enough data to undo it and shows a notice with Undo.
- A hard-days heads-up (two of tempo, threshold, intervals or long on consecutive days, one of
  them edited) never blocks.
- Plan match score = how closely a completed workout followed its prescribed
  session (distance, pace, effort). Proposed bands: 90 and above "On plan",
  70 to 89 "Mostly on plan", below 70 "Off plan". Confirm the weights before
  hardcoding them.
- Morning check is suggest-and-confirm. It runs when the day's sleep data arrives,
  not at a fixed clock time, and compares to the user's own baseline. Until
  data arrives, show "no data yet" instead of guessing.
- Memory: raw AthleteNote entries plus one consolidated AthleteProfile summary,
  rewritten when the app opens after enough new notes. Every prompt includes the
  summary.

## Data principles
- The LLM drafts plan STRUCTURE; code fills details and validates. Every LLM plan passes
  PlanValidator before it is saved. LLM prompts contain summaries only, never raw routes or
  personal names.
- Never hardcode the on-device context size: read it at runtime.
- The default plan generator is Automatic (PCC light, then on-device, then TemplatePlanGenerator), each model
  wrapped in ValidatingPlanGenerator (2 attempts). DEBUG fakes use the template unless -planGenerator is given.
- Model Lab is DEBUG-only (Home header ladybug button or long-press, "Model Lab"). -planGenerator, -planFallback
  and -fakeLLM are DEBUG launch arguments. Claude in the Lab needs consent ("Send summaries to
  Anthropic?") and a key; Release builds never use Claude for plans or suggested changes.
- Code computes everything numeric: pace, splits, HR drift, zones, percentiles,
  PR detection, plan match, fit labels. The LLM only reasons over compact summaries
  and writes text or a structured plan.
- Never send raw routes or trackpoints to the LLM. Pass missing data as explicit unknown.
- Raw route points and sample series never leave Infrastructure and are never stored or sent. Only
  derived analysis (splits, laps, zone histogram, totals) is cached and used in prompts.
- Code decides assessment (distance check, effort check with heart-rate reserve zones, verdict, recovery
  context). Code produces Findings and assessments. The LLM only writes the note from them. The note is
  checked by DetailedNoteGuard (lengths, numbers, paces, km marks, zones), retried once with the issues,
  otherwise a rule-based note (TemplateDetailedNoteWriter) is stored. Km marks and zones in a note must appear in the facts
  that were sent (ranges allowed, decimals allowed, 0 allowed). Distances are checked as numbers, not as marks. Next is the
  next unfinished session on or after today. Recent sessions never include sessions after the described run. Coach notes live in GRDB (coach_note),
  analyses in workout_analysis. Constants: AssessmentRules and AnalysisRules.
- Tempo, threshold and intervals are not effort-assessed as a whole: each planned block gets a target from
  EffortTargetTable; threshold and intervals blocks (and any block with reps) are "mixed", not assessed.
  Verdict chips stay neutral until the rating slice.
- The coach notes' model: Automatic (Private Cloud Compute, then on-device, then the rules) unless the
  DEBUG Lab's "Use for coach notes" picked one. Claude goes through the same SpendGate and ledger
  (purpose workoutNote).
- Validate LLM plan output against domain rules before saving (training days only
  on chosen weekdays, nothing after race day). Retry once, then show an error.
- Norm tables live in the bundled Norms.json behind NormRepository. Every table carries
  its source. Never add or change a value without a citation. Unsupported age or sex
  hides the scale. Reference data is not stored in the user database.
- DEBUG personas exist only under #if DEBUG.
- DEBUG launch arguments (compiled out of release): -useInMemoryStores, -persona,
  -simulate, -authorized, -resetCache, -today yyyy-MM-dd (shifts the Clock),
  -seedPlan (an in-memory database seeded with SeedPlan, fake Health, skips onboarding),
  -fakeRuns (runs derived from the plan as seeded, on original dates, so edits never change
  them; kept in memory), -fakeSleep <normal|short|noStages|
  none|denied|stale|locked|failed|nap|twoSources> (sleep scenarios built from today,
  kept in memory), -fakeRecovery <mock|good|strained|noHrv|none|denied|stale|locked|
  failed|fewSamples|fallback> (HRV and resting HR scenarios built from today, kept in
  memory; use fallback with -fakeSleep none). The Home header's ladybug button (or a long-press) opens "Copy
  plan JSON" (with originalDate and isMissed per session and an `edits` array), "Copy sleep JSON" (window, sources, nights, the shown night's segments,
  ignored counts), "Copy recovery JSON" (window, sources, HRV nights, resting HR days, the
  shown night's and day's samples, ignored counts, whether the SDK has an RMSSD type) and
  "Reset plan". -startTab <home|calendar> picks the opening tab; -calendarMonth yyyy-MM the
  Calendar's opening month (clamped to the plan). -planGenerator <template|onDevice|pcc.light|
  pcc.moderate|pcc.deep|anthropic.haiku55|anthropic.sonnet55|anthropic.opus55|anthropic.fable51> picks
  the generator for Race setup -> Generating; -planFallback adds the template behind a model; -fakeLLM
  <ok|invalidPlan|unavailable|quota|slow|anthropicOk|noKey|badKey|credits|rateLimited> gives canned model
  answers (with an in-memory ledger, settings and secret store, never the database or Keychain); -planDelay <seconds> delays the template (absent or 0: no delay).
  -fakeWorkoutDetail <tempo|easyDrift|noHr|paused|laps|flat|tempoVaried> gives canned workout detail (no HealthKit;
  flat is 5.7 km of identical 6:00 /km, 158 bpm splits, tempoVaried is the tempo; the Lab's workout note shows a "Flat data"
  chip when WorkoutAnalysis.flatSeries is true, a diagnostic that never changes a note);
  -fakeCoachNote <ok|slow|fail|rules> canned notes (fail throws once, rules forces the rule-based note);
  -fakeHeartRateHigh makes easy runs average 153 bpm; -coachModel <auto|template|onDevice|pcc.light|...|
  anthropic.haiku55|...> overrides the notes' model. With fake Health and neither -fakeCoachNote nor
  -coachModel, the rules write the notes. The fakes use the profile max 182, resting 49.
  The Home ladybug menu also has "Copy coach note facts"; Session detail's note menu has "Copy facts",
  "Show facts", "Copy analysis JSON" and "Copy note JSON".
  -feedbackPopup lets the after-workout popup open with fake Health (it never does otherwise); -fakeAdjust
  <ok|fail> gives canned suggested changes (fail: the rules); without it, fakes use the rules. -fakeRuns also
  gives a 32-minute strength workout on every strength session's original date before today.
  -planGenerator also takes auto. -allowAnyDistance lifts the race range (any distance up to 250 km) for
  that run. The Model Lab's plan draft has fixed races R1 (10 km, 8 weeks), R2 (half, 12 weeks), R3 (15 km,
  10 weeks, Tue/Thu/Sat/Sun) and R4 (30 km, 14 weeks, Mon/Wed/Fri/Sun), with fallback fitness 20 km a week.
- The snapshot cache holds summaries only (never raw routes, workout lists or the date
  of birth). Reference data and user data stay separate.
- The raw JSON view exists only in DEBUG builds.
- Every generator's output must pass PlanValidator before it is saved.
- Database = GRDB (v7). It holds the plan, the plan edit log, the usage ledger, coach notes
  (v3_coach_note), workout analyses (v4_workout_analysis), strength sessions (v5_plan_strength), workout
  feedback (v6_workout_feedback) and suggested changes (v7_plan_adjustment) (trainer.sqlite in Application Support). Caches (runs, sleep, recovery, snapshot) stay JSON files. A plan in the old
  TrainingPlan.json is imported once at launch and the file is renamed, never deleted.
- The API key lives only in the Keychain (SecretStore). Never in source, Info.plist, logs,
  analytics or any copied JSON. The ledger stores token counts and costs, never prompts or outputs.
- Every LLM call (Apple and Anthropic, Lab and real flow) is recorded in the usage ledger (GRDB
  table llm_usage, migration v2_llm_usage) by the adapter itself. Costs are estimates from the
  bundled Prices.json (lastVerified date inside). When Anthropic changes prices, edit that file and
  bump lastVerified. Anthropic's Console is the source of truth. Use a dedicated API key for this app.
- Spend guards block runs before they are sent (per-run and monthly caps, consent, key, price
  table; SpendGate). Each LLM attempt is recorded separately, including retries. Money is Decimal
  and micro-dollars, never Double.

## Open decisions (ask the user before deciding)
- Apple Foundation Models (on-device and PCC) are built; PCC needs a managed entitlement that
  is not added yet.
- Claude via the official ClaudeForFoundationModels package (beta, OS 27). A key per user is
  needed if the app is ever shared.

## Layout: one local Swift Package, one app target
Each layer is a separate Swift Package target so the compiler enforces the
dependency direction. Never add a target dependency that breaks this table.

Packages/<CoreName>/        local Swift Package linked by the app target
  Sources/Domain/           depends on: nothing (Foundation only)
  Sources/Application/      depends on: Domain
  Sources/Infrastructure/   depends on: Application, Domain
  Tests/DomainTests/        Swift Testing, fakes only
  Tests/ApplicationTests/   Swift Testing, fakes only
<AppName>/                  SwiftUI app target: views, view models, composition root
<AppName>Tests/             unit tests for app-target code, Swift Testing
<AppName>UITests/           XCTest UI tests (the only place XCTest is used)

### Domain
Plain structs and enums: Workout, PlannedSession, Evaluation, MorningCheck,
HealthMetric, AthleteNote, AthleteProfile, RaceProfile, FitnessBaseline,
PersonalRecord, WorkoutSummary. Pure rules live here as plain functions: pace,
splits, HR drift, zones, percentile lookup, PR detection, plan-fit labels,
plan match, plan-change rules (move, swap, missed). Foundation only.

### Application
- Ports (protocols only): CoachingModel, HealthDataSource, SecretStore, Clock,
  and one small repository protocol per entity.
- Use cases (one type per job, dependencies via initializer): ReadHealthBaseline,
  SuggestPlans, GeneratePlan, SyncHealthWorkouts, EvaluateWorkout,
  CheckMorningReadiness, RespondToMorningCheck, ApplyPlanEdit (move, swap and missed are
  PlanEdit cases validated by PlanEditValidator), UndoPlanEdit, GetCalendarMonth, ConsolidateMemory.

### Infrastructure
HealthKitDataSource, Foundation Models adapters (Apple's models and Claude), Keychain SecretStore,
local-database repositories, SystemClock, plus a factory (e.g. PersistenceFactory)
that builds the database container and repositories.

### App
SwiftUI views, view models and the composition root. The `@main` App struct (or a
CompositionRoot type it owns) is the ONLY place that constructs infrastructure
types and injects them into use cases and view models.

## Storage rules
- Storage: None was chosen at project creation. Do not add `.modelContainer(...)`,
  `@Query` or `@Environment(\.modelContext)` to the app target or any view.
- The database library lives only in Infrastructure/Persistence behind repository
  protocols. The composition root calls the factory and never imports SwiftData
  or GRDB.
- Persistence models are mapped to and from domain structs inside the repository.
- `import GRDB` only in Infrastructure/Persistence (and the persistence tests). GRDB types never
  leave Infrastructure.
- Migrations are named and additive (v1_plan, ...). Never edit a migration after it has
  shipped: every change is a new migration.

## Import rules (check before finishing any task)
- `import HealthKit` only inside Infrastructure's HealthKit adapter.
- `import SwiftData` / `import GRDB` only inside Infrastructure's persistence.
- `import FoundationModels` only in Infrastructure/LLM (and its adapter tests).
- `import ClaudeForFoundationModels` only in Infrastructure/LLM (and its adapter tests).
- `import SwiftUI` only in the app target.
- Domain and Application import Foundation only.
- No `HKWorkout`, `HKSample`, persistence models, `URLSession` or `URLError` may
  appear in any signature in Domain, Application or the app target. Adapters
  convert them to domain types at the boundary.

## SOLID checklist (apply before finishing any change)
- Single Responsibility: one use case, one job. If its name needs "and", split it.
  View models only call use cases and format results. Repositories only persist.
- Open/Closed: a new LLM provider or health source = one new type in
  Infrastructure plus one line in the composition root. If a use case has to change,
  the port is incomplete: fix the port.
- Liskov: any two conformances of a port are interchangeable. No provider-specific
  special cases inside a use case.
- Interface Segregation: small protocols per entity or concern.
- Dependency Inversion: depend on protocols, injected via initializers. No
  singletons, no `.shared`, no constructing a concrete adapter inside a use case.

## Pragmatism rule
Ports are mandatory only for: health data source, LLM, persistence, clock, secret
storage. Elsewhere prefer plain concrete types. No protocol for a type with one
implementation and no seam.

## Swift-specific rules
- Domain types are structs/enums, `Sendable`, and `Equatable`/`Codable` where useful.
- Ports are `async throws` protocols. Mutable shared state lives in actors.
- `@MainActor` only on view models and UI code.
- Typed domain errors (HealthDataUnavailable, LLMUnavailable). Adapters translate
  `HKError`/`URLError` into them.
- No force unwraps, no `try!`, no `fatalError` outside tests.
- Inject `Clock` instead of calling `Date()` in logic.

## Design: "Volt" (dark, neon accent)
Keep every value in one Theme file, never inline in views.
- Colors: background #0B0C0E, card #15171A, inner card #111316, card border
  #22252A, text #F4F5F6, muted text #8B9096, soft text #C7CAD1, accent (lime)
  #C6FF3D with dark text #0B0C0E on it. Derive soft/faint/line tints from the
  accent at about 15%, 7% and 33% opacity.
- Status colors, used only for ratings and deltas: green #5BE08C, amber #FFC640,
  red #FF6B5E. Never use the accent for a rating.
- completed = #7C9CFF with a check badge. Green, amber and red remain reserved for ratings and
  deltas. The accent lime means today and selection. Session status looks come from
  SessionStatusPresentation only.
- Type: Sora (600/700) for headings and big numbers, DM Sans for body. Both are
  open-licensed; bundle the font files and register them in the Info.plist
  (check the license files when bundling).
- Shape: cards radius 24 to 28, small tiles 18 to 20, pills fully rounded. Touch
  targets at least 44 pt. Floating pill tab bar (Home, Calendar) with the active tab
  filled in the accent.
- Week strip: pill days, selected day filled in the accent, session-type icon
  under the date.
- Scales: right is always better. Bell curve for VO2 max, five equal percentile
  bands for resting heart rate, a marker bubble reading "You · <value>".
- No emoji, no decorative gradients. Real buttons and links with accessibility labels.

## Testing
- Unit tests use Swift Testing: `import Testing`, `@Test`, `#expect`, `#require`,
  suites as structs. No new XCTestCase classes for unit tests.
- Domain and Application tests use fake ports. No HealthKit, network or real
  database. Use hand-calculated expectations for pace, percentile, PR and plan-match logic.
- UI tests use XCTest (`XCUIApplication`) because Swift Testing has no UI tests.
  Keep them to a few happy-path flows (onboarding, move a session). Give key
  controls accessibility identifiers and launch with an argument that makes the
  composition root use in-memory fakes.
- SwiftUI previews use in-memory fakes.

## When adding a new adapter
1. Confirm the port already covers the need. Extend the protocol first if not.
2. Add the conforming type under Infrastructure.
3. Wire it in the composition root.
4. Do not touch any use case, domain type or view to support it.

## Before finishing any task
Re-read the diff. Did Domain or Application gain an import they should not have?
Does any signature expose a framework type? Did anything outside the composition
root construct an infrastructure type? Did a view reach for the database or
HealthKit directly? Did any file-import code sneak in? Fix before calling it done.

## Starting point and Health data rules
- Source names never carry personal names: the adapter normalizes "<Name>'s Apple
  Watch/iPhone/iPad" to the device name.
- PRs are scaled estimates (show "est."), flagged "Older" after 365 days, and are
  display-only, never used for plan sizing.
- Plan fit labels come from 28-day running volume and longest run, never from PRs or
  VO2 max. Thresholds live in PlanFitRules.swift.
- Never hardcode a user name in the UI.
