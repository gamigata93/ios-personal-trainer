import Foundation
import Domain
import Application
@testable import HybridAthlete

/// A health source for app tests: chosen request status, optional locked
/// workouts, and an optional thrown error when access is requested.
actor StubHealthDataSource: HealthDataSource {
    private var status: HealthAuthorizationRequestStatus
    private let lockedWorkouts: Bool
    private let requestError: HealthDataError?
    private(set) var requestCount = 0

    init(status: HealthAuthorizationRequestStatus = .alreadyRequested, lockedWorkouts: Bool = false, requestError: HealthDataError? = nil) {
        self.status = status
        self.lockedWorkouts = lockedWorkouts
        self.requestError = requestError
    }

    func authorizationRequestStatus() async -> HealthAuthorizationRequestStatus { status }

    func requestAccess() async throws {
        requestCount += 1
        if let requestError { throw requestError }
        status = .alreadyRequested
    }

    func readProfile() async throws -> HealthProfile { HealthProfile(ageYears: 34, biologicalSex: .male) }

    func readSamples(_ kind: HealthMetricKind, since: Date?, limit: Int?) async throws -> [HealthSample] {
        [HealthSample(value: kind == .vo2Max ? 46 : 52, unit: kind.unitLabel, date: FixedClock.date, sourceName: "Apple Watch")]
    }

    func readWorkouts(routeCheckLimit: Int) async throws -> [WorkoutSummary] {
        if lockedWorkouts { throw HealthDataError.locked }
        let start = FixedClock.date.addingTimeInterval(-86_400)
        return [WorkoutSummary(
            id: "run", activityType: .running, sourceName: "Apple Watch", start: start,
            end: start.addingTimeInterval(1_500), durationSeconds: 1_500, distanceMeters: 5_000,
            averageHeartRate: 160, maxHeartRate: 175, activeEnergyKilocalories: 320,
            elevationAscendedMeters: nil, hasRoute: true
        )]
    }
}

extension StubHealthDataSource {
    func runningWorkouts(from: LocalDate, to: LocalDate) async throws -> [RunSummary] { [] }
    func sleepSegments(from: Date, to: Date) async throws -> [SleepSegment] { [] }
    func hrvSamples(from: Date, to: Date) async throws -> [HRVSample] { [] }
    func restingHeartRateSamples(from: Date, to: Date) async throws -> [RestingHRSample] { [] }
}

actor StubSnapshotCache: SnapshotCache {
    private var stored: CachedSnapshot?

    init(_ stored: CachedSnapshot? = nil) {
        self.stored = stored
    }

    func load() async -> CachedSnapshot? { stored }
    func save(_ snapshot: CachedSnapshot) async throws { stored = snapshot }
}

/// Norms are not under test here; every lookup fails, so scales are hidden.
struct NoNorms: NormRepository {
    func table(metric: NormMetric, sex: NormSex, ageYears: Int) async throws -> NormTable? { throw NormDataError.missing }
    func coverage(metric: NormMetric, sex: NormSex) async throws -> ClosedRange<Int>? { throw NormDataError.missing }
}

actor StubPlans: PlanRepository {
    private var plan: TrainingPlan?
    private(set) var saveCount = 0

    init(plan: TrainingPlan? = nil) {
        self.plan = plan
    }

    init(hasPlan: Bool) {
        self.plan = hasPlan ? StubPlans.sample : nil
    }

    func save(_ plan: TrainingPlan) async throws {
        saveCount += 1
        self.plan = plan
    }

    func loadActive() async -> TrainingPlan? { plan }
    func hasActivePlan() async -> Bool { plan != nil }
    func deleteActive() async throws { plan = nil }

    // MARK: Edits, applied with the Domain rules

    private var edits: [PlanEditRecord] = []
    /// When set, edits and undos throw it and change nothing.
    private var editFailure: (any Error)?

    func setEditFailure(_ error: (any Error)?) { editFailure = error }

    func applyEdit(planId: String, edit: PlanEdit) async throws -> EditReceipt {
        if let editFailure { throw editFailure }
        guard let current = plan, current.id == planId else { throw PlanRepositoryError.noActivePlan }
        guard let change = PlanChange.make(edit, current: PlanEditApplier.placements(of: current)) else {
            throw PlanRepositoryError.stalePlan
        }
        plan = PlanEditApplier.apply(change, to: current)
        let record = PlanEditRecord(id: Int64(edits.count + 1), createdAt: FixedClock.date, edit: edit, change: change, undoneAt: nil)
        edits.append(record)
        return EditReceipt(editId: record.id)
    }

    func undoEdit(planId: String, editId: Int64) async throws {
        if let editFailure { throw editFailure }
        guard
            let current = plan,
            let index = edits.firstIndex(where: { $0.id == editId }),
            edits[index].undoneAt == nil,
            edits[index].change.after.allSatisfy({ PlanEditApplier.placements(of: current)[$0.sessionId] == $0 })
        else { throw PlanRepositoryError.cannotUndo }
        let record = edits[index]
        plan = PlanEditApplier.apply(record.change.inverse, to: current)
        edits[index] = PlanEditRecord(id: record.id, createdAt: record.createdAt, edit: record.edit, change: record.change, undoneAt: FixedClock.date)
    }

    func recentEdits(planId: String, limit: Int) async throws -> [PlanEditRecord] {
        Array(edits.reversed().prefix(limit))
    }

    static let sample = TrainingPlan(
        id: "sample", createdAt: FixedClock.date, generatedBy: "test", planKind: .tenK,
        race: RaceSetup(distanceKm: 10, elevationGainM: 0, raceDate: LocalDate(year: 2026, month: 12, day: 6), trainingDays: [.tuesday, .sunday]),
        planStart: LocalDate(year: 2026, month: 10, day: 12), weeks: []
    )
}

/// Always fails, so the generating screen's error path can be tested.
struct FailingGenerator: PlanGenerator {
    func generate(_ request: PlanRequest) async throws -> TrainingPlan {
        throw HealthDataError.failed
    }
}

struct FixedClock: Clock {
    static let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func now() -> Date { Self.date }
}

actor StubRunsCache: CompletedRunsCache {
    private var stored: CachedRuns?

    init(_ stored: CachedRuns? = nil) {
        self.stored = stored
    }

    func load() async -> CachedRuns? { stored }
    func save(_ runs: CachedRuns) async throws { stored = runs }
}

actor StubSleepCache: SleepCache {
    private var stored: CachedSleep?

    init(_ stored: CachedSleep? = nil) {
        self.stored = stored
    }

    func load() async -> CachedSleep? { stored }
    func save(_ sleep: CachedSleep) async throws { stored = sleep }
}

actor StubRecoveryCache: RecoveryCache {
    private var stored: CachedRecovery?

    init(_ stored: CachedRecovery? = nil) {
        self.stored = stored
    }

    func load() async -> CachedRecovery? { stored }
    func save(_ recovery: CachedRecovery) async throws { stored = recovery }
}

extension ActivePlanStore {
    /// The store over a repository with the real use cases.
    convenience init(plans: any PlanRepository, clock: any Clock = FixedClock(), calendar: Calendar = .current) {
        self.init(
            loadActivePlan: LoadActivePlan(plans: plans),
            applyPlanEdit: ApplyPlanEdit(plans: plans, clock: clock, calendar: calendar),
            undoPlanEdit: UndoPlanEdit(plans: plans),
            loadRecentPlanEdits: LoadRecentPlanEdits(plans: plans)
        )
    }
}
