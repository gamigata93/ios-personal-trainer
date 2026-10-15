import Foundation
import Domain

/// One section's new state during a refresh, delivered as soon as it is known.
public enum HealthRefreshUpdate: Sendable, Equatable {
    /// Always first: when this refresh began.
    case started(Date)
    case profile(SectionState<ProfileSummary>)
    case vo2Max(SectionState<VO2MaxSummary>)
    case restingHeartRate(SectionState<RestingHeartRateSummary>)
    case workouts(SectionState<WorkoutsSummary>)
    /// Always last: the full in-memory read, for the DEBUG raw-data view. Never cached.
    case finished(HealthSnapshot)

    public var section: HealthSection? {
        switch self {
        case .profile: .profile
        case .vo2Max: .vo2Max
        case .restingHeartRate: .restingHeartRate
        case .workouts: .workouts
        case .started, .finished: nil
        }
    }
}

/// Reads Apple Health in the background and keeps the cache current. Wraps
/// `ReadHealthBaseline`: sections run in parallel and fail on their own. Every
/// section that reads fine is merged into the cache and saved at once; a locked
/// section falls back to its cached value.
public struct RefreshHealthSnapshot: Sendable {
    /// A refresh on returning to the foreground only runs when the last one is older than this.
    public static let foregroundRefreshInterval: TimeInterval = 5 * 60

    private let readHealthBaseline: ReadHealthBaseline
    private let cache: any SnapshotCache
    private let clock: any Clock

    public init(health: any HealthDataSource, cache: any SnapshotCache, clock: any Clock) {
        self.readHealthBaseline = ReadHealthBaseline(health: health, clock: clock)
        self.cache = cache
        self.clock = clock
    }

    /// Whether a refresh that started at `lastRefreshStart` is old enough to repeat.
    public func isStale(lastRefreshStart: Date?) -> Bool {
        guard let lastRefreshStart else { return true }
        return clock.now().timeIntervalSince(lastRefreshStart) >= Self.foregroundRefreshInterval
    }

    public func execute() -> AsyncStream<HealthRefreshUpdate> {
        AsyncStream { continuation in
            let task = Task {
                continuation.yield(.started(clock.now()))
                var cached = await cache.load()
                var workouts: WorkoutsSection?
                var runHeartRate: RunHeartRateSection?

                for await update in readHealthBaseline.execute() {
                    let now = clock.now()
                    switch update {
                    case .profile(let section):
                        let value = section.status == .ok
                            ? ProfileSummary(ageYears: section.ageYears, biologicalSex: section.biologicalSex)
                            : nil
                        let state = Self.state(section.status, value: value, cached: cached?.profile, now: now)
                        if case .ready(let fresh, _, _) = state {
                            cached = await save((cached ?? .empty(at: now)).with(profile: CachedSection(value: fresh, asOf: now), at: now))
                        }
                        continuation.yield(.profile(state))

                    case .vo2Max(let section):
                        let value = section.latest.map { VO2MaxSummary(latest: $0, recent: section.recent) }
                        let state = Self.state(section.status, value: value, cached: cached?.vo2Max, now: now)
                        if case .ready(let fresh, _, _) = state {
                            cached = await save((cached ?? .empty(at: now)).with(vo2Max: CachedSection(value: fresh, asOf: now), at: now))
                        }
                        continuation.yield(.vo2Max(state))

                    case .restingHeartRate(let section):
                        let value = section.latest.map {
                            RestingHeartRateSummary(latest: $0, average30Days: section.average30Days, sampleCount30Days: section.sampleCount30Days)
                        }
                        let state = Self.state(section.status, value: value, cached: cached?.restingHeartRate, now: now)
                        if case .ready(let fresh, _, _) = state {
                            cached = await save((cached ?? .empty(at: now)).with(restingHeartRate: CachedSection(value: fresh, asOf: now), at: now))
                        }
                        continuation.yield(.restingHeartRate(state))

                    // The workouts read reports the list, then the two sections derived
                    // from it; the summary is complete once the records arrive.
                    case .workouts(let section):
                        workouts = section
                    case .runHeartRate(let section):
                        runHeartRate = section
                    case .personalRecords(let records):
                        guard let workouts else { break }
                        let value = workouts.status == .ok
                            ? WorkoutsSummary.summarizing(
                                workouts,
                                runHeartRate: runHeartRate ?? .unread(workouts.status),
                                personalRecords: records,
                                now: now
                            )
                            : nil
                        let state = Self.state(workouts.status, value: value, cached: cached?.workouts, now: now)
                        if case .ready(let fresh, _, _) = state {
                            cached = await save((cached ?? .empty(at: now)).with(workouts: CachedSection(value: fresh, asOf: now), at: now))
                        }
                        continuation.yield(.workouts(state))

                    case .finished(let snapshot):
                        continuation.yield(.finished(snapshot))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Saves and returns the merged snapshot. A failed save keeps the merge in
    /// memory for this refresh; the next refresh tries again.
    private func save(_ snapshot: CachedSnapshot) async -> CachedSnapshot {
        try? await cache.save(snapshot)
        return snapshot
    }

    /// ok -> ready, locked -> the cached value behind a lock, empty -> empty,
    /// anything else -> failed.
    static func state<Value>(
        _ status: ReadStatus,
        value: Value?,
        cached: CachedSection<Value>?,
        now: Date
    ) -> SectionState<Value> {
        switch status {
        case .ok:
            guard let value else { return .emptyOrNotAllowed }
            return .ready(value, asOf: now, fromCache: false)
        case .locked:
            return .locked(cachedValue: cached?.value, asOf: cached?.asOf)
        case .emptyOrNotAllowed:
            return .emptyOrNotAllowed
        case .error:
            return .failed
        }
    }
}
