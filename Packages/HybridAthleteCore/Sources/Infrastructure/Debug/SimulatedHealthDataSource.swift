#if DEBUG
import Foundation
import Application
import Domain

/// How a simulated read behaves. DEBUG builds only.
public enum SimulationMode: String, Sendable, CaseIterable {
    /// Answers straight from the underlying fake.
    case normal
    /// Sections finish one after another: VO2 max and profile at 1.5 s,
    /// resting heart rate at 2.5 s, workouts at 4 s.
    case slow
    /// Every read fails as if the phone were locked.
    case locked
    /// Every read comes back empty.
    case empty
    /// Every read fails as not allowed.
    case denied
}

/// Wraps a fake source to act out timing and failure modes, and to behave like
/// the permission sheet: not requested until `requestAccess` is called.
public actor SimulatedHealthDataSource: HealthDataSource {
    private let base: any HealthDataSource
    private let mode: SimulationMode
    private var requested: Bool

    public init(base: any HealthDataSource, mode: SimulationMode, alreadyRequested: Bool = false) {
        self.base = base
        self.mode = mode
        self.requested = alreadyRequested
    }

    public func authorizationRequestStatus() async -> HealthAuthorizationRequestStatus {
        requested ? .alreadyRequested : .shouldRequest
    }

    public func requestAccess() async throws {
        requested = true
    }

    public func readProfile() async throws -> HealthProfile {
        try await simulate(after: 1.5, empty: HealthProfile(ageYears: nil, biologicalSex: nil)) {
            try await base.readProfile()
        }
    }

    public func readSamples(_ kind: HealthMetricKind, since: Date?, limit: Int?) async throws -> [HealthSample] {
        let delay: Double = kind == .vo2Max ? 1.5 : 2.5
        return try await simulate(after: delay, empty: []) {
            try await base.readSamples(kind, since: since, limit: limit)
        }
    }

    public func readWorkouts(routeCheckLimit: Int) async throws -> [WorkoutSummary] {
        try await simulate(after: 4, empty: []) {
            try await base.readWorkouts(routeCheckLimit: routeCheckLimit)
        }
    }

    public func runningWorkouts(from: LocalDate, to: LocalDate) async throws -> [RunSummary] {
        try await simulate(after: 4, empty: []) {
            try await base.runningWorkouts(from: from, to: to)
        }
    }

    public func sleepSegments(from: Date, to: Date) async throws -> [SleepSegment] {
        try await simulate(after: 2.5, empty: []) {
            try await base.sleepSegments(from: from, to: to)
        }
    }

    public func hrvSamples(from: Date, to: Date) async throws -> [HRVSample] {
        try await simulate(after: 2.5, empty: []) {
            try await base.hrvSamples(from: from, to: to)
        }
    }

    public func restingHeartRateSamples(from: Date, to: Date) async throws -> [RestingHRSample] {
        try await simulate(after: 2.5, empty: []) {
            try await base.restingHeartRateSamples(from: from, to: to)
        }
    }

    private func simulate<T: Sendable>(
        after seconds: Double,
        empty: T,
        read: () async throws -> T
    ) async throws -> T {
        switch mode {
        case .normal: return try await read()
        case .slow:
            try await Task.sleep(for: .seconds(seconds))
            return try await read()
        case .locked: throw HealthDataError.locked
        case .empty: return empty
        case .denied: throw HealthDataError.notAllowed
        }
    }
}

/// A cache that, when empty, starts from a seed. Lets `-simulate locked` show
/// cached values on the first launch. DEBUG builds only.
public actor SeededSnapshotCache: SnapshotCache {
    private let underlying: any SnapshotCache
    private let seed: @Sendable () async -> CachedSnapshot?

    public init(underlying: any SnapshotCache, seed: @escaping @Sendable () async -> CachedSnapshot?) {
        self.underlying = underlying
        self.seed = seed
    }

    public func load() async -> CachedSnapshot? {
        if let stored = await underlying.load() { return stored }
        guard let seeded = await seed() else { return nil }
        try? await underlying.save(seeded)
        return seeded
    }

    public func save(_ snapshot: CachedSnapshot) async throws {
        try await underlying.save(snapshot)
    }
}
#endif
