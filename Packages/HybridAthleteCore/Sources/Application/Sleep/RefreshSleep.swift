import Foundation
import Domain

/// The result of one sleep read.
public struct SleepRefreshResult: Sendable, Equatable {
    public let state: SectionState<[SleepNight]>
    /// The newest night is later than any cached one (or nothing was cached).
    /// Nothing uses it yet; the morning check will.
    public let isNewNight: Bool
    /// What was read, kept in memory for the DEBUG export. Never cached.
    public let read: SleepRead?
}

/// The raw read behind a refresh. In memory only.
public struct SleepRead: Sendable, Equatable {
    public let readAt: Date
    /// The calendar nights were built with (its time zone goes into the export).
    public let calendar: Calendar
    public let window: DateInterval
    public let segments: [SleepSegment]
    public let build: SleepNightBuilder.Result
}

/// Reads sleep from Health, builds nights and keeps the cache current.
public struct RefreshSleep: Sendable {
    private let health: any HealthDataSource
    private let cache: any SleepCache
    private let clock: any Clock
    private let calendar: Calendar

    public init(health: any HealthDataSource, cache: any SleepCache, clock: any Clock, calendar: Calendar) {
        self.health = health
        self.cache = cache
        self.clock = clock
        self.calendar = calendar
    }

    /// From local noon `SleepRules.queryWindowDays` days before today to now.
    public func window() -> DateInterval {
        let now = clock.now()
        let first = LocalDate(date: now, calendar: calendar).adding(days: -SleepRules.queryWindowDays)
        let start = first.date(in: calendar)
            .flatMap { calendar.date(byAdding: .hour, value: SleepRules.queryWindowStartHour, to: $0) } ?? now
        return DateInterval(start: min(start, now), end: now)
    }

    /// Fresh nights replace cached nights that wake inside the window; older
    /// cached nights stay; the newest `SleepRules.cachedNights` are kept.
    /// Locked shows the cache; an empty read falls back to the cache; any other
    /// failure keeps the cache and reports failed.
    public func execute() async -> SleepRefreshResult {
        let window = window()
        let cached = await cache.load()
        let segments: [SleepSegment]
        do {
            segments = try await mappingHealthErrors { try await health.sleepSegments(from: window.start, to: window.end) }
        } catch {
            switch error {
            case .locked:
                return SleepRefreshResult(state: .locked(cachedValue: cached?.nights, asOf: cached?.generatedAt), isNewNight: false, read: nil)
            case .notAllowed:
                return SleepRefreshResult(state: .emptyOrNotAllowed, isNewNight: false, read: nil)
            case .unavailable, .failed:
                return SleepRefreshResult(state: .failed, isNewNight: false, read: nil)
            }
        }

        let build = SleepNightBuilder.build(segments, calendar: calendar)
        let read = SleepRead(readAt: clock.now(), calendar: calendar, window: window, segments: segments, build: build)
        if segments.isEmpty {
            guard let cached, !cached.nights.isEmpty else {
                return SleepRefreshResult(state: .emptyOrNotAllowed, isNewNight: false, read: read)
            }
            return SleepRefreshResult(state: .ready(cached.nights, asOf: cached.generatedAt, fromCache: true), isNewNight: false, read: read)
        }

        // Nights waking on or after the day after the window's first day were read in full.
        let firstFull = LocalDate(date: window.start, calendar: calendar).adding(days: 1)
        let kept = (cached?.nights ?? []).filter { $0.wakeDate < firstFull }
        let merged = Array((kept + build.nights).sorted { $0.wakeDate < $1.wakeDate }.suffix(SleepRules.cachedNights))
        let now = clock.now()
        try? await cache.save(CachedSleep(generatedAt: now, nights: merged))

        let newestCached = cached?.nights.map(\.wakeDate).max()
        let newest = merged.map(\.wakeDate).max()
        let isNewNight = newest.map { newest in newestCached.map { newest > $0 } ?? true } ?? false
        return SleepRefreshResult(state: .ready(merged, asOf: now, fromCache: false), isNewNight: isNewNight, read: read)
    }
}

/// The cached nights, shown before Health is read.
public struct LoadCachedSleep: Sendable {
    private let cache: any SleepCache

    public init(cache: any SleepCache) {
        self.cache = cache
    }

    /// Ready from the cache, or loading when nothing is cached.
    public func execute() async -> SectionState<[SleepNight]> {
        guard let cached = await cache.load(), !cached.nights.isEmpty else { return .loading }
        return .ready(cached.nights, asOf: cached.generatedAt, fromCache: true)
    }
}
