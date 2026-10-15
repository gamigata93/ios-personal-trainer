#if DEBUG
import Foundation
import Application
import Domain

/// The `-fakeSleep <scenario>` launch argument. Nights are built from the
/// injected clock's today, so it works with `-today`. DEBUG builds only.
public enum FakeSleepScenario: String, Sendable, CaseIterable {
    /// 15 nights. Today 450 min (deep 75, core 275, REM 100, awake 5); the 7
    /// before, oldest to newest, 420, 400, 450, 380, 460, 430, 410; older 420.
    case normal
    /// Today 372 min (deep 50, core 222, REM 100, awake 12); the 7 before 432 each.
    case short
    /// Like normal, but unspecified sleep only.
    case noStages
    /// Health answers with one short nap, so no night qualifies: "No sleep data yet".
    case none
    /// Reads fail as not allowed.
    case denied
    /// Like normal, but the newest night is 5 days ago.
    case stale
    /// Reads fail as locked; the cache starts with the normal nights.
    case locked
    /// Reads fail with a generic error.
    case failed
    /// Normal plus a 40-minute nap at 14:00 today.
    case nap
    /// Normal (Apple Watch) plus "Zepp" with 430 min for today's night.
    case twoSources
}

/// Serves a scenario's sleep; everything else comes from the wrapped source.
public struct FakeSleepHealthDataSource: HealthDataSource {
    /// Every fake night ends at 06:50 local.
    static let wakeHour = 6
    static let wakeMinute = 50

    private let base: any HealthDataSource
    private let scenario: FakeSleepScenario
    private let clock: any Clock
    private let calendar: Calendar

    public init(base: any HealthDataSource, scenario: FakeSleepScenario, clock: any Clock, calendar: Calendar) {
        self.base = base
        self.scenario = scenario
        self.clock = clock
        self.calendar = calendar
    }

    public func authorizationRequestStatus() async -> HealthAuthorizationRequestStatus { await base.authorizationRequestStatus() }
    public func requestAccess() async throws { try await base.requestAccess() }
    public func readProfile() async throws -> HealthProfile { try await base.readProfile() }

    public func readSamples(_ kind: HealthMetricKind, since: Date?, limit: Int?) async throws -> [HealthSample] {
        try await base.readSamples(kind, since: since, limit: limit)
    }

    public func readWorkouts(routeCheckLimit: Int) async throws -> [WorkoutSummary] {
        try await base.readWorkouts(routeCheckLimit: routeCheckLimit)
    }

    public func hrvSamples(from: Date, to: Date) async throws -> [HRVSample] {
        try await base.hrvSamples(from: from, to: to)
    }

    public func restingHeartRateSamples(from: Date, to: Date) async throws -> [RestingHRSample] {
        try await base.restingHeartRateSamples(from: from, to: to)
    }

    public func runningWorkouts(from: LocalDate, to: LocalDate) async throws -> [RunSummary] {
        try await base.runningWorkouts(from: from, to: to)
    }

    /// Everything ending after `from`. The end of the window is not applied, so
    /// today's night shows whatever the time of day.
    public func sleepSegments(from: Date, to: Date) async throws -> [SleepSegment] {
        switch scenario {
        case .denied: throw HealthDataError.notAllowed
        case .locked: throw HealthDataError.locked
        case .failed: throw HealthDataError.failed
        default: return Self.segments(scenario, today: LocalDate(date: clock.now(), calendar: calendar), calendar: calendar)
            .filter { $0.end > from }
        }
    }

    /// The cache a scenario starts with: for `locked`, the normal nights read an
    /// hour ago; otherwise none.
    public static func seededCache(_ scenario: FakeSleepScenario, clock: any Clock, calendar: Calendar) -> CachedSleep? {
        guard scenario == .locked else { return nil }
        let today = LocalDate(date: clock.now(), calendar: calendar)
        let nights = SleepNightBuilder.build(Self.segments(.normal, today: today, calendar: calendar), calendar: calendar).nights
        return CachedSleep(generatedAt: clock.now().addingTimeInterval(-3_600), nights: nights)
    }

    // MARK: Scenarios

    private static let normalBefore = [410, 430, 460, 380, 450, 400, 420] // 1 to 7 days ago
    private static let olderMinutes = 420
    private static let nightCount = 15

    static func segments(_ scenario: FakeSleepScenario, today: LocalDate, calendar: Calendar) -> [SleepSegment] {
        let watch = SleepRules.preferredSource
        switch scenario {
        case .normal, .locked:
            return normalNights(today: today, shift: 0, unspecified: false, calendar: calendar)
        case .noStages:
            return normalNights(today: today, shift: 0, unspecified: true, calendar: calendar)
        case .stale:
            return normalNights(today: today, shift: 5, unspecified: false, calendar: calendar)
        case .short:
            return night(wake: today, Split(deep: 50, core: 222, rem: 100, awake: 12), source: watch, calendar: calendar)
                + (1...7).flatMap { night(wake: today.adding(days: -$0), .typical(432), source: watch, calendar: calendar) }
        case .none:
            return nap(on: today.adding(days: -2), minutes: 30, calendar: calendar)
        case .nap:
            return normalNights(today: today, shift: 0, unspecified: false, calendar: calendar)
                + nap(on: today, minutes: 40, calendar: calendar)
        case .twoSources:
            return normalNights(today: today, shift: 0, unspecified: false, calendar: calendar)
                + night(wake: today, Split(unspecified: 430), source: "Zepp", calendar: calendar)
        case .denied, .failed:
            return []
        }
    }

    private static func normalNights(today: LocalDate, shift: Int, unspecified: Bool, calendar: Calendar) -> [SleepSegment] {
        (0..<nightCount).flatMap { daysAgo -> [SleepSegment] in
            let split: Split
            switch daysAgo {
            case 0: split = Split(deep: 75, core: 275, rem: 100, awake: 5)
            case 1...7: split = .typical(normalBefore[daysAgo - 1])
            default: split = .typical(olderMinutes)
            }
            return night(
                wake: today.adding(days: -(daysAgo + shift)),
                unspecified ? Split(unspecified: split.asleep) : split,
                source: SleepRules.preferredSource,
                calendar: calendar
            )
        }
    }

    /// Minutes of each stage in one night.
    struct Split {
        var deep = 0, core = 0, rem = 0, awake = 0, unspecified = 0

        var asleep: Int { deep + core + rem + unspecified }

        /// About 17% deep, 22% REM, the rest core, and 5 minutes awake.
        static func typical(_ asleep: Int) -> Split {
            let deep = asleep * 17 / 100
            let rem = asleep * 22 / 100
            return Split(deep: deep, core: asleep - deep - rem, rem: rem, awake: 5)
        }
    }

    /// Core, deep, awake, core, REM (awake only between asleep stages), ending at 06:50.
    private static func night(wake: LocalDate, _ split: Split, source: String, calendar: Calendar) -> [SleepSegment] {
        guard
            let midnight = wake.date(in: calendar),
            let end = calendar.date(bySettingHour: wakeHour, minute: wakeMinute, second: 0, of: midnight)
        else { return [] }
        let firstCore = split.core / 2
        let parts: [(SleepStage, Int)] = [
            (.asleepUnspecified, split.unspecified), (.core, firstCore), (.deep, split.deep),
            (.awake, split.awake), (.core, split.core - firstCore), (.rem, split.rem),
        ].filter { $0.1 > 0 }
        var cursor = end.addingTimeInterval(-Double(parts.map(\.1).reduce(0, +) * 60))
        return parts.map { stage, minutes in
            let next = cursor.addingTimeInterval(Double(minutes * 60))
            defer { cursor = next }
            return SleepSegment(start: cursor, end: next, stage: stage, source: source)
        }
    }

    /// Core sleep from 14:00 local.
    private static func nap(on day: LocalDate, minutes: Int, calendar: Calendar) -> [SleepSegment] {
        guard
            let midnight = day.date(in: calendar),
            let start = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: midnight)
        else { return [] }
        return [SleepSegment(start: start, end: start.addingTimeInterval(Double(minutes * 60)), stage: .core, source: SleepRules.preferredSource)]
    }
}
#endif
