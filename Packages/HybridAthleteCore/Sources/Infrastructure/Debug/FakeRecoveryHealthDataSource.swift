#if DEBUG
import Foundation
import Application
import Domain

/// The `-fakeRecovery <scenario>` launch argument. Values are built from the
/// injected clock's today, so it works with `-today`. DEBUG builds only.
///
/// Prior values cover the seven days before today, oldest to newest: HRV nightly
/// means 62, 60, 64, 59, 61, 63, 62 (four samples each) and resting heart rate
/// 50, 51, 50, 52, 50, 51, 50. Older days: HRV 62 and resting heart rate 50.
public enum FakeRecoveryScenario: String, Sendable, CaseIterable {
    /// HRV today 58 (52, 60, 64, 56 at 00:30, 02:10, 04:20, 06:10); resting HR today 49.
    case mock
    /// HRV today 66, resting HR today 48.
    case good
    /// HRV today 45 (40, 46, 48, 46), resting HR today 54.
    case strained
    /// No HRV samples; resting HR as mock.
    case noHrv
    /// No samples at all and nothing cached.
    case none
    /// Both reads fail as not allowed.
    case denied
    /// As mock, but the newest entries are 5 days old.
    case stale
    /// Reads fail as locked; the cache starts with the mock summaries.
    case locked
    /// Reads fail with a generic error.
    case failed
    /// As mock, but today's night has a single HRV sample.
    case fewSamples
    /// As mock. Use with `-fakeSleep none`: the HRV then comes from the 00:00 to 08:00 window.
    case fallback
}

/// Serves a scenario's HRV and resting heart rate; everything else comes from
/// the wrapped source.
public struct FakeRecoveryHealthDataSource: HealthDataSource {
    private let base: any HealthDataSource
    private let scenario: FakeRecoveryScenario
    private let clock: any Clock
    private let calendar: Calendar

    public init(base: any HealthDataSource, scenario: FakeRecoveryScenario, clock: any Clock, calendar: Calendar) {
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

    public func runningWorkouts(from: LocalDate, to: LocalDate) async throws -> [RunSummary] {
        try await base.runningWorkouts(from: from, to: to)
    }

    public func sleepSegments(from: Date, to: Date) async throws -> [SleepSegment] {
        try await base.sleepSegments(from: from, to: to)
    }

    /// Everything from `from` on. The end of the window is not applied, so
    /// today's values show whatever the time of day.
    public func hrvSamples(from: Date, to: Date) async throws -> [HRVSample] {
        try failIfAsked()
        return Self.hrv(scenario, today: today, calendar: calendar).filter { $0.date >= from }
    }

    public func restingHeartRateSamples(from: Date, to: Date) async throws -> [RestingHRSample] {
        try failIfAsked()
        return Self.restingHR(scenario, today: today, calendar: calendar).filter { $0.endDate >= from }
    }

    /// The cache a scenario starts with: for `locked`, the mock summaries read
    /// an hour ago; otherwise none.
    public static func seededCache(_ scenario: FakeRecoveryScenario, clock: any Clock, calendar: Calendar) -> CachedRecovery? {
        guard scenario == .locked else { return nil }
        let today = LocalDate(date: clock.now(), calendar: calendar)
        return CachedRecovery(
            generatedAt: clock.now().addingTimeInterval(-3_600),
            hrv: HRVNightBuilder.build(samples: hrv(.mock, today: today, calendar: calendar), sleepNights: [], calendar: calendar, today: today).nights,
            restingHr: RestingHRDayBuilder.build(restingHR(.mock, today: today, calendar: calendar), calendar: calendar).days
        )
    }

    private var today: LocalDate { LocalDate(date: clock.now(), calendar: calendar) }

    private func failIfAsked() throws {
        switch scenario {
        case .denied: throw HealthDataError.notAllowed
        case .locked: throw HealthDataError.locked
        case .failed: throw HealthDataError.failed
        default: break
        }
    }

    // MARK: Scenarios

    /// 7 days ago first, yesterday last.
    private static let priorHRV: [Double] = [62, 60, 64, 59, 61, 63, 62]
    private static let priorRestingHR: [Double] = [50, 51, 50, 52, 50, 51, 50]
    private static let olderHRV: Double = 62
    private static let olderRestingHR: Double = 50
    private static let dayCount = 15
    /// Sample times on each wake date, local.
    private static let hrvTimes = [(0, 30), (2, 10), (4, 20), (6, 10)]
    /// Offsets from the night's mean, so four samples average exactly to it.
    private static let hrvSpread: [Double] = [-6, 2, 6, -2]

    static func hrv(_ scenario: FakeRecoveryScenario, today: LocalDate, calendar: Calendar) -> [HRVSample] {
        switch scenario {
        case .noHrv, .none, .denied, .locked, .failed:
            return []
        case .mock, .fallback:
            return hrvNights(today: today, todayValues: [52, 60, 64, 56], shift: 0, calendar: calendar)
        case .good:
            return hrvNights(today: today, todayValues: [60, 68, 72, 64], shift: 0, calendar: calendar)
        case .strained:
            return hrvNights(today: today, todayValues: [40, 46, 48, 46], shift: 0, calendar: calendar)
        case .stale:
            return hrvNights(today: today, todayValues: [52, 60, 64, 56], shift: 5, calendar: calendar)
        case .fewSamples:
            return hrvNights(today: today, todayValues: [58], shift: 0, calendar: calendar)
        }
    }

    static func restingHR(_ scenario: FakeRecoveryScenario, today: LocalDate, calendar: Calendar) -> [RestingHRSample] {
        switch scenario {
        case .none, .denied, .locked, .failed:
            return []
        case .mock, .noHrv, .fewSamples, .fallback:
            return restingDays(today: today, todayValue: 49, shift: 0, calendar: calendar)
        case .good:
            return restingDays(today: today, todayValue: 48, shift: 0, calendar: calendar)
        case .strained:
            return restingDays(today: today, todayValue: 54, shift: 0, calendar: calendar)
        case .stale:
            return restingDays(today: today, todayValue: 49, shift: 5, calendar: calendar)
        }
    }

    /// Today's values at 00:30, 02:10, 04:20 and 06:10 (in that order), then four
    /// samples per earlier night around its mean.
    private static func hrvNights(today: LocalDate, todayValues: [Double], shift: Int, calendar: Calendar) -> [HRVSample] {
        (0..<dayCount).reversed().flatMap { daysAgo -> [HRVSample] in
            let values: [Double]
            switch daysAgo {
            case 0: values = todayValues
            case 1...7: values = hrvSpread.map { priorHRV[7 - daysAgo] + $0 }
            default: values = hrvSpread.map { olderHRV + $0 }
            }
            let day = today.adding(days: -(daysAgo + shift))
            return zip(hrvTimes, values).compactMap { time, value in
                at(day, hour: time.0, minute: time.1, calendar: calendar)
                    .map { HRVSample(date: $0, valueMs: value, source: RecoveryRules.preferredSource) }
            }
        }
    }

    /// Today's sample ends at 07:30 local, earlier days at 18:50.
    private static func restingDays(today: LocalDate, todayValue: Double, shift: Int, calendar: Calendar) -> [RestingHRSample] {
        (0..<dayCount).reversed().compactMap { daysAgo -> RestingHRSample? in
            let value: Double
            switch daysAgo {
            case 0: value = todayValue
            case 1...7: value = priorRestingHR[7 - daysAgo]
            default: value = olderRestingHR
            }
            let day = today.adding(days: -(daysAgo + shift))
            let end = daysAgo == 0 ? at(day, hour: 7, minute: 30, calendar: calendar) : at(day, hour: 18, minute: 50, calendar: calendar)
            return end.map { RestingHRSample(endDate: $0, bpm: value, source: RecoveryRules.preferredSource) }
        }
    }

    private static func at(_ day: LocalDate, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        day.date(in: calendar).flatMap { calendar.date(bySettingHour: hour, minute: minute, second: 0, of: $0) }
    }
}
#endif
