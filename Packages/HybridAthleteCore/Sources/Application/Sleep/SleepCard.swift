import Foundation
import Domain

/// The Sleep card on Home: what to show for the section's state.
public struct SleepCard: Sendable, Equatable {
    public enum Body: Sendable, Equatable {
        /// Nothing cached yet and the first read is running.
        case loading
        case overview(SleepOverview)
        /// Health answered, but no night qualifies.
        case noData
        /// "Last recorded: Sat 17 Oct."
        case noRecent(lastRecorded: String)
        /// Nothing read: no data, or access was declined (HealthKit does not say which).
        case emptyOrNotAllowed
        /// Locked with nothing cached.
        case lockedNoCache
        case failed
    }

    public let body: Body

    /// Builds the card from the section state with the overview rules. The
    /// locked and updated lines belong to the Recovery section.
    static func make(_ state: SectionState<[SleepNight]>, overview: GetSleepOverview, today: LocalDate) -> SleepCard {
        func body(for nights: [SleepNight]) -> Body {
            switch overview.execute(nights: nights, today: today) {
            case .ready(let ready): .overview(ready)
            case .noData: .noData
            case .noRecent(let last): .noRecent(lastRecorded: "Last recorded: \(HomeFormat.shortDate(last)).")
            }
        }
        switch state {
        case .loading: return SleepCard(body: .loading)
        case .ready(let nights, _, _): return SleepCard(body: body(for: nights))
        case .locked(let cached, _): return SleepCard(body: cached.map(body(for:)) ?? .lockedNoCache)
        case .emptyOrNotAllowed: return SleepCard(body: .emptyOrNotAllowed)
        case .failed: return SleepCard(body: .failed)
        }
    }
}
