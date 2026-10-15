import Foundation
import Application
import Domain

/// Returns preset results per section. Any section can be held open until a
/// test releases it, to control the order sections finish in.
actor FakeHealthDataSource: HealthDataSource {
    var requestStatus: HealthAuthorizationRequestStatus = .alreadyRequested
    var profile: Result<HealthProfile, HealthDataError> = .success(HealthProfile(ageYears: 34, biologicalSex: .female))
    var vo2Max: Result<[HealthSample], HealthDataError> = .success([FakeHealthDataSource.sample(46, unit: "ml/(kg·min)")])
    var restingHeartRate: Result<[HealthSample], HealthDataError> = .success([FakeHealthDataSource.sample(52, unit: "bpm")])
    var workouts: Result<[WorkoutSummary], HealthDataError> = .success([])
    var runs: Result<[RunSummary], HealthDataError> = .success([])
    private(set) var runRanges: [ClosedRange<LocalDate>] = []
    var sleep: Result<[SleepSegment], HealthDataError> = .success([])
    private(set) var sleepWindows: [DateInterval] = []
    var hrv: Result<[HRVSample], HealthDataError> = .success([])
    var restingHR: Result<[RestingHRSample], HealthDataError> = .success([])
    private(set) var hrvWindows: [DateInterval] = []
    /// "sleep", "hrv", "restingHr" as each read starts and ends ("sleep.start", "sleep.end").
    private(set) var events: [String] = []
    private var heldReads: Set<String> = []
    private var readGates: [String: CheckedContinuation<Void, Never>] = [:]
    private(set) var requestCount = 0
    private var held: Set<HealthSection> = []
    private var gates: [HealthSection: CheckedContinuation<Void, Never>] = [:]

    func set(
        requestStatus: HealthAuthorizationRequestStatus? = nil,
        profile: Result<HealthProfile, HealthDataError>? = nil,
        vo2Max: Result<[HealthSample], HealthDataError>? = nil,
        restingHeartRate: Result<[HealthSample], HealthDataError>? = nil,
        workouts: Result<[WorkoutSummary], HealthDataError>? = nil
    ) {
        if let requestStatus { self.requestStatus = requestStatus }
        if let profile { self.profile = profile }
        if let vo2Max { self.vo2Max = vo2Max }
        if let restingHeartRate { self.restingHeartRate = restingHeartRate }
        if let workouts { self.workouts = workouts }
    }

    func hold(_ sections: HealthSection...) {
        held.formUnion(sections)
    }

    func release(_ section: HealthSection) {
        held.remove(section)
        gates.removeValue(forKey: section)?.resume()
    }

    func set(runs: Result<[RunSummary], HealthDataError>) {
        self.runs = runs
    }

    func set(sleep: Result<[SleepSegment], HealthDataError>) {
        self.sleep = sleep
    }

    func set(hrv: Result<[HRVSample], HealthDataError>) {
        self.hrv = hrv
    }

    func set(restingHR: Result<[RestingHRSample], HealthDataError>) {
        self.restingHR = restingHR
    }

    /// Holds the "sleep", "hrv" or "restingHr" read open until released.
    func holdRead(_ name: String) {
        heldReads.insert(name)
    }

    func releaseRead(_ name: String) {
        heldReads.remove(name)
        readGates.removeValue(forKey: name)?.resume()
    }

    /// Whether a read has started and is waiting at its gate.
    func isWaiting(_ name: String) -> Bool {
        readGates[name] != nil
    }

    private func gate(_ name: String) async {
        events.append("\(name).start")
        if heldReads.contains(name) {
            await withCheckedContinuation { readGates[name] = $0 }
        }
        events.append("\(name).end")
    }

    func holdWorkouts() { hold(.workouts) }
    func releaseWorkouts() { release(.workouts) }

    func authorizationRequestStatus() async -> HealthAuthorizationRequestStatus { requestStatus }

    func requestAccess() async throws {
        requestCount += 1
        requestStatus = .alreadyRequested
    }

    func readProfile() async throws -> HealthProfile {
        await wait(.profile)
        return try profile.get()
    }

    func readSamples(_ kind: HealthMetricKind, since: Date?, limit: Int?) async throws -> [HealthSample] {
        await wait(kind == .vo2Max ? .vo2Max : .restingHeartRate)
        let all = try (kind == .vo2Max ? vo2Max : restingHeartRate).get()
        let windowed = all.filter { sample in since.map { sample.date >= $0 } ?? true }
        return Array(windowed.prefix(limit ?? windowed.count))
    }

    func readWorkouts(routeCheckLimit: Int) async throws -> [WorkoutSummary] {
        await wait(.workouts)
        return try workouts.get()
    }

    func runningWorkouts(from: LocalDate, to: LocalDate) async throws -> [RunSummary] {
        runRanges.append(from...to)
        return try runs.get()
    }

    func sleepSegments(from: Date, to: Date) async throws -> [SleepSegment] {
        sleepWindows.append(DateInterval(start: from, end: to))
        await gate("sleep")
        return try sleep.get()
    }

    func hrvSamples(from: Date, to: Date) async throws -> [HRVSample] {
        hrvWindows.append(DateInterval(start: from, end: to))
        await gate("hrv")
        return try hrv.get()
    }

    func restingHeartRateSamples(from: Date, to: Date) async throws -> [RestingHRSample] {
        await gate("restingHr")
        return try restingHR.get()
    }

    private func wait(_ section: HealthSection) async {
        guard held.contains(section) else { return }
        await withCheckedContinuation { gates[section] = $0 }
    }

    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static func sample(_ value: Double, unit: String, daysAgo: Double = 1) -> HealthSample {
        HealthSample(value: value, unit: unit, date: now.addingTimeInterval(-daysAgo * 86_400), sourceName: "Apple Watch")
    }

    static func run(id: String, meters: Double, seconds: Double, heartRate: Double?, daysAgo: Double = 3) -> WorkoutSummary {
        let start = now.addingTimeInterval(-daysAgo * 86_400)
        return WorkoutSummary(
            id: id, activityType: .running, sourceName: "WorkOutdoors", start: start,
            end: start.addingTimeInterval(seconds), durationSeconds: seconds, distanceMeters: meters,
            averageHeartRate: heartRate, maxHeartRate: nil, activeEnergyKilocalories: nil,
            elevationAscendedMeters: nil, hasRoute: true
        )
    }
}

/// An in-memory cache that records saves and can pretend its file was corrupt.
actor FakeSnapshotCache: SnapshotCache {
    private(set) var stored: CachedSnapshot?
    private(set) var saveCount = 0
    private let corrupt: Bool

    init(stored: CachedSnapshot? = nil, corrupt: Bool = false) {
        self.stored = stored
        self.corrupt = corrupt
    }

    func load() async -> CachedSnapshot? {
        corrupt ? nil : stored
    }

    func save(_ snapshot: CachedSnapshot) async throws {
        saveCount += 1
        stored = snapshot
    }
}

/// Plan storage in memory that counts saves and can fail on save. Edits use the
/// Domain applier; `editFailure` makes the next edits throw.
actor FakePlanRepository: PlanRepository {
    private(set) var plan: TrainingPlan?
    private(set) var saveCount = 0
    private(set) var edits: [PlanEditRecord] = []
    private let failsOnSave: Bool
    var editFailure: (any Error)?

    init(plan: TrainingPlan? = nil, failsOnSave: Bool = false) {
        self.plan = plan
        self.failsOnSave = failsOnSave
    }

    func setEditFailure(_ error: (any Error)?) { editFailure = error }

    func applyEdit(planId: String, edit: PlanEdit) async throws -> EditReceipt {
        if let editFailure { throw editFailure }
        guard let current = plan, current.id == planId else { throw PlanRepositoryError.noActivePlan }
        guard let change = PlanChange.make(edit, current: PlanEditApplier.placements(of: current)) else {
            throw PlanRepositoryError.stalePlan
        }
        plan = PlanEditApplier.apply(change, to: current)
        let record = PlanEditRecord(id: Int64(edits.count + 1), createdAt: FakeHealthDataSource.now, edit: edit, change: change, undoneAt: nil)
        edits.append(record)
        return EditReceipt(editId: record.id)
    }

    func undoEdit(planId: String, editId: Int64) async throws {
        guard
            let current = plan,
            let index = edits.firstIndex(where: { $0.id == editId }),
            edits[index].undoneAt == nil,
            edits[index].change.after.allSatisfy({ PlanEditApplier.placements(of: current)[$0.sessionId] == $0 })
        else { throw PlanRepositoryError.cannotUndo }
        let record = edits[index]
        plan = PlanEditApplier.apply(record.change.inverse, to: current)
        edits[index] = PlanEditRecord(id: record.id, createdAt: record.createdAt, edit: record.edit, change: record.change, undoneAt: FakeHealthDataSource.now)
    }

    func recentEdits(planId: String, limit: Int) async throws -> [PlanEditRecord] {
        Array(edits.reversed().prefix(limit))
    }

    func save(_ plan: TrainingPlan) async throws {
        if failsOnSave { throw FakeStorageError() }
        saveCount += 1
        self.plan = plan
    }

    func loadActive() async -> TrainingPlan? { plan }
    func hasActivePlan() async -> Bool { plan != nil }
    func deleteActive() async throws { plan = nil }

    static let samplePlan = TrainingPlan(
        id: "sample", createdAt: FakeHealthDataSource.now, generatedBy: "test", planKind: .tenK,
        race: RaceSetup(distanceKm: 10, elevationGainM: 0, raceDate: LocalDate(year: 2026, month: 12, day: 6), trainingDays: [.tuesday, .sunday]),
        planStart: LocalDate(year: 2026, month: 10, day: 12), weeks: []
    )
}

struct FakeStorageError: Error {}
