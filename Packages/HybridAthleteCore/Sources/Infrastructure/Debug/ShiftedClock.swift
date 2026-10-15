#if DEBUG
import Foundation
import Application
import Domain

/// The `-today yyyy-MM-dd` launch argument: the real time of day, moved to
/// another date, so mid-plan states can be previewed. DEBUG builds only.
public struct ShiftedClock: Clock {
    private let base: any Clock
    private let offset: TimeInterval

    public init(base: any Clock, today: LocalDate, calendar: Calendar) {
        self.base = base
        let now = base.now()
        let target = today.date(in: calendar) ?? now
        self.offset = target.timeIntervalSince(calendar.startOfDay(for: now))
    }

    public func now() -> Date {
        base.now().addingTimeInterval(offset)
    }
}
#endif
