import Foundation
import Synchronization
import Application

final class FakeClock: Clock {
    private let current: Mutex<Date>

    init(_ date: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) {
        current = Mutex(date)
    }

    func now() -> Date {
        current.withLock { $0 }
    }
}
