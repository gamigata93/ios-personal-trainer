import Foundation
import Domain

/// The result of one HRV read.
public struct HRVRefreshResult: Sendable, Equatable {
    public let state: SectionState<[HRVNight]>
    /// What was read, kept in memory for the DEBUG export. Never cached.
    public let read: HRVRead?
}

/// The raw HRV read behind a refresh. In memory only.
public struct HRVRead: Sendable, Equatable {
    public let readAt: Date
    public let calendar: Calendar
    public let window: DateInterval
    public let samples: [HRVSample]
    public let build: HRVNightBuilder.Result
}

/// The result of one resting heart rate read.
public struct RestingHRRefreshResult: Sendable, Equatable {
    public let state: SectionState<[RestingHRDay]>
    /// What was read, kept in memory for the DEBUG export. Never cached.
    public let read: RestingHRRead?
}

/// The raw resting heart rate read behind a refresh. In memory only.
public struct RestingHRRead: Sendable, Equatable {
    public let readAt: Date
    public let calendar: Calendar
    public let window: DateInterval
    public let samples: [RestingHRSample]
    public let build: RestingHRDayBuilder.Result
}

/// Reads HRV and resting heart rate from Health, builds the summaries and
/// keeps the cache current. The two metrics are read separately so each can be
/// shown as soon as it is ready; cache updates are serialized so the two never
/// overwrite each other.
public actor RefreshRecovery {
    private let health: any HealthDataSource
    private let cache: any RecoveryCache
    private let clock: any Clock
    private let calendar: Calendar
    private var lastCacheUpdate: Task<Void, Never>?

    public init(health: any HealthDataSource, cache: any RecoveryCache, clock: any Clock, calendar: Calendar) {
        self.health = health
        self.cache = cache
        self.clock = clock
        self.calendar = calendar
    }

    /// From local noon `RecoveryRules.queryWindowDays` days before today to now.
    public nonisolated func window() -> DateInterval {
        let now = clock.now()
        let first = LocalDate(date: now, calendar: calendar).adding(days: -RecoveryRules.queryWindowDays)
        let start = first.date(in: calendar)
            .flatMap { calendar.date(byAdding: .hour, value: RecoveryRules.queryWindowStartHour, to: $0) } ?? now
        return DateInterval(start: min(start, now), end: now)
    }

    /// Nightly HRV inside `sleepNights`' windows (or the overnight fallback).
    public func refreshHRV(sleepNights: [SleepNight]) async -> HRVRefreshResult {
        let window = window()
        let today = LocalDate(date: window.end, calendar: calendar)
        let outcome = await refresh(
            cached: \.hrv,
            date: \.wakeDate,
            read: { try await self.health.hrvSamples(from: window.start, to: window.end) },
            build: { HRVNightBuilder.build(samples: $0, sleepNights: sleepNights, calendar: self.calendar, today: today) },
            values: \.nights,
            store: { cached, merged, now in
                CachedRecovery(generatedAt: now, hrv: merged, restingHr: cached?.restingHr ?? [])
            }
        )
        let read = outcome.read.map {
            HRVRead(readAt: window.end, calendar: calendar, window: window, samples: $0.samples, build: $0.build)
        }
        return HRVRefreshResult(state: outcome.state, read: read)
    }

    /// Daily resting heart rate on local dates.
    public func refreshRestingHR() async -> RestingHRRefreshResult {
        let window = window()
        let outcome = await refresh(
            cached: \.restingHr,
            date: \.date,
            read: { try await self.health.restingHeartRateSamples(from: window.start, to: window.end) },
            build: { RestingHRDayBuilder.build($0, calendar: self.calendar) },
            values: \.days,
            store: { cached, merged, now in
                CachedRecovery(generatedAt: now, hrv: cached?.hrv ?? [], restingHr: merged)
            }
        )
        let read = outcome.read.map {
            RestingHRRead(readAt: window.end, calendar: calendar, window: window, samples: $0.samples, build: $0.build)
        }
        return RestingHRRefreshResult(state: outcome.state, read: read)
    }

    // MARK: Shared rules

    private struct Outcome<Value: Sendable, Sample: Sendable, Build: Sendable>: Sendable {
        let state: SectionState<[Value]>
        let read: (samples: [Sample], build: Build)?
    }

    /// The same rules as `RefreshSleep`: locked shows the cache; an empty read
    /// falls back to the cache; any other failure keeps the cache and reports
    /// failed. Fresh entries replace cached ones from the day after the window's
    /// first day; older cached entries stay; the newest `cachedEntries` are kept.
    private func refresh<Value: Sendable, Sample: Sendable, Build: Sendable>(
        cached keyPath: KeyPath<CachedRecovery, [Value]> & Sendable,
        date: KeyPath<Value, LocalDate> & Sendable,
        read: @Sendable () async throws -> [Sample],
        build: @Sendable ([Sample]) -> Build,
        values: KeyPath<Build, [Value]> & Sendable,
        store: @escaping @Sendable (CachedRecovery?, [Value], Date) -> CachedRecovery
    ) async -> Outcome<Value, Sample, Build> {
        let window = window()
        let samples: [Sample]
        do {
            samples = try await mappingHealthErrors { try await read() }
        } catch {
            let cached = await cache.load()
            switch error {
            case .locked:
                let values = cached.map { $0[keyPath: keyPath] }.flatMap { $0.isEmpty ? nil : $0 }
                return Outcome(state: .locked(cachedValue: values, asOf: values == nil ? nil : cached?.generatedAt), read: nil)
            case .notAllowed:
                return Outcome(state: .emptyOrNotAllowed, read: nil)
            case .unavailable, .failed:
                return Outcome(state: .failed, read: nil)
            }
        }

        let built = build(samples)
        if samples.isEmpty {
            let cached = await cache.load()
            guard let cached, !cached[keyPath: keyPath].isEmpty else {
                return Outcome(state: .emptyOrNotAllowed, read: (samples, built))
            }
            return Outcome(state: .ready(cached[keyPath: keyPath], asOf: cached.generatedAt, fromCache: true), read: (samples, built))
        }

        let firstFull = LocalDate(date: window.start, calendar: calendar).adding(days: 1)
        let fresh = built[keyPath: values]
        let now = clock.now()
        let merged = await updateCache { cached in
            let kept = (cached?[keyPath: keyPath] ?? []).filter { $0[keyPath: date] < firstFull }
            let keptDates = Set(kept.map { $0[keyPath: date] })
            let all = kept + fresh.filter { !keptDates.contains($0[keyPath: date]) }
            let merged = Array(all.sorted { $0[keyPath: date] < $1[keyPath: date] }.suffix(RecoveryRules.cachedEntries))
            return (store(cached, merged, now), merged)
        }
        return Outcome(state: .ready(merged, asOf: now, fromCache: false), read: (samples, built))
    }

    /// Load, change and save one at a time, so the HRV and resting heart rate
    /// refreshes never overwrite each other's half of the file.
    private func updateCache<Result: Sendable>(
        _ change: @escaping @Sendable (CachedRecovery?) -> (CachedRecovery, Result)
    ) async -> Result {
        let previous = lastCacheUpdate
        let cache = self.cache
        let task = Task<Result, Never> {
            await previous?.value
            let (updated, result) = change(await cache.load())
            try? await cache.save(updated)
            return result
        }
        lastCacheUpdate = Task { _ = await task.value }
        return await task.value
    }
}

/// The cached summaries, shown before Health is read.
public struct LoadCachedRecovery: Sendable {
    private let cache: any RecoveryCache

    public init(cache: any RecoveryCache) {
        self.cache = cache
    }

    /// Ready from the cache per metric, or loading when nothing is cached.
    public func execute() async -> (hrv: SectionState<[HRVNight]>, restingHr: SectionState<[RestingHRDay]>) {
        guard let cached = await cache.load() else { return (.loading, .loading) }
        return (
            cached.hrv.isEmpty ? .loading : .ready(cached.hrv, asOf: cached.generatedAt, fromCache: true),
            cached.restingHr.isEmpty ? .loading : .ready(cached.restingHr, asOf: cached.generatedAt, fromCache: true)
        )
    }
}
