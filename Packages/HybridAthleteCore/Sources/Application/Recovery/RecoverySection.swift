import Foundation
import Domain

/// Each Recovery metric's section state, as Home keeps them.
public struct RecoveryStates: Sendable, Equatable {
    public var sleep: SectionState<[SleepNight]>
    public var hrv: SectionState<[HRVNight]>
    public var restingHr: SectionState<[RestingHRDay]>

    public init(
        sleep: SectionState<[SleepNight]> = .loading,
        hrv: SectionState<[HRVNight]> = .loading,
        restingHr: SectionState<[RestingHRDay]> = .loading
    ) {
        self.sleep = sleep
        self.hrv = hrv
        self.restingHr = restingHr
    }

    public static let loading = RecoveryStates()
}

/// One compact card on Home (HRV or resting heart rate).
public struct RecoveryMetricCard: Sendable, Equatable {
    public enum Body: Sendable, Equatable {
        /// Nothing cached yet and the first read is running.
        case loading
        case overview(RecoveryMetricOverview)
        /// No value: none recorded, or access was declined (HealthKit does not say which).
        case noData
        /// "Last: Sat 17 Oct."
        case noRecent(last: String)
        /// Locked with nothing cached.
        case lockedNoCache
        case failed
    }

    public let body: Body
}

/// The Recovery section on Home: the Sleep card, the two compact cards and the
/// section-level lines.
public struct RecoveryOverview: Sendable, Equatable {
    public let sleep: SleepCard
    public let hrv: RecoveryMetricCard
    public let restingHr: RecoveryMetricCard
    /// "Updated 5 min ago": the newest data time across the three metrics.
    public let updatedLabel: String?
    /// "Your phone is locked. Showing recovery from today 07:40." when any metric is locked.
    public let lockedNotice: String?
    /// The Settings hint when any metric read nothing and nothing is cached.
    public let accessNotice: String?

    static func make(
        _ states: RecoveryStates,
        sleepOverview: GetSleepOverview,
        recoveryOverview: GetRecoveryOverview,
        today: LocalDate,
        now: Date,
        calendar: Calendar
    ) -> RecoveryOverview {
        func since(_ date: Date) -> String { UpdatedLabel.text(now: now, then: date, calendar: calendar) }

        let locked = [
            (states.sleep.isLocked, states.sleep.asOf),
            (states.hrv.isLocked, states.hrv.asOf),
            (states.restingHr.isLocked, states.restingHr.asOf),
        ].filter(\.0)
        let lockedNotice: String? = locked.isEmpty ? nil : {
            guard let asOf = locked.compactMap(\.1).max() else {
                return "Your phone is locked. Recovery updates after you unlock it."
            }
            return "Your phone is locked. Showing recovery from \(since(asOf))."
        }()
        let isEmpty = [states.sleep.isEmptyOrNotAllowed, states.hrv.isEmptyOrNotAllowed, states.restingHr.isEmptyOrNotAllowed]
        let newest = [states.sleep.asOf, states.hrv.asOf, states.restingHr.asOf].compactMap { $0 }.max()

        return RecoveryOverview(
            sleep: SleepCard.make(states.sleep, overview: sleepOverview, today: today),
            hrv: card(states.hrv) { recoveryOverview.hrvState($0, today: today) },
            restingHr: card(states.restingHr) { recoveryOverview.restingHRState($0, today: today) },
            updatedLabel: newest.map { "Updated \(since($0))" },
            lockedNotice: lockedNotice,
            accessNotice: isEmpty.contains(true)
                ? "If you declined access, allow it in Settings, Health, Data Access & Devices."
                : nil
        )
    }

    private static func card<Value>(
        _ state: SectionState<[Value]>,
        overview: ([Value]) -> RecoveryMetricState
    ) -> RecoveryMetricCard {
        func body(_ values: [Value]) -> RecoveryMetricCard.Body {
            switch overview(values) {
            case .ready(let ready): .overview(ready)
            case .noData: .noData
            case .noRecent(let last): .noRecent(last: "Last: \(HomeFormat.shortDate(last)).")
            }
        }
        switch state {
        case .loading: return RecoveryMetricCard(body: .loading)
        case .ready(let values, _, _): return RecoveryMetricCard(body: body(values))
        case .locked(let cached, _): return RecoveryMetricCard(body: cached.map(body) ?? .lockedNoCache)
        case .emptyOrNotAllowed: return RecoveryMetricCard(body: .noData)
        case .failed: return RecoveryMetricCard(body: .failed)
        }
    }
}

private extension SectionState {
    var isEmptyOrNotAllowed: Bool {
        if case .emptyOrNotAllowed = self { true } else { false }
    }
}
