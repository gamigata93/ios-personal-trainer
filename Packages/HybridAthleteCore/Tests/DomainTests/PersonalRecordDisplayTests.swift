import Foundation
import Testing
import Domain

struct PersonalRecordDisplayTests {
    private let now = UTC.date(2026, 10, 9)

    private func record(daysAgo: Double, normalized: Bool = false, isNew: Bool = false) -> PersonalRecord {
        PersonalRecord(
            distance: .fiveK, timeSeconds: 1_500, actualDistanceMeters: normalized ? 5_040 : 5_000,
            timeIsNormalized: normalized, date: now.addingTimeInterval(-daysAgo * 86_400),
            workoutId: "w", isNew: isNew
        )
    }

    @Test func normalizedTimeIsEstimated() {
        #expect(PersonalRecordDisplay(record: record(daysAgo: 1, normalized: true), now: now).isEstimated)
        #expect(!PersonalRecordDisplay(record: record(daysAgo: 1), now: now).isEstimated)
    }

    @Test func olderAfterThreeHundredSixtyFiveDays() {
        #expect(!PersonalRecordDisplay(record: record(daysAgo: 364), now: now).isOlder)
        #expect(!PersonalRecordDisplay(record: record(daysAgo: 365), now: now).isOlder)
        #expect(PersonalRecordDisplay(record: record(daysAgo: 366), now: now).isOlder)
    }

    @Test func newComesFromTheThirtyDayRule() {
        // Built with the detector so the 30-day window is the real rule.
        let run = { (daysAgo: Double) in
            Fixture.workout(daysAgo: daysAgo, meters: 5_000, seconds: 1_500)
        }
        let recent = PersonalRecordDetector.records(in: [run(30)], now: Fixture.now)[0]
        let old = PersonalRecordDetector.records(in: [run(31)], now: Fixture.now)[0]
        #expect(PersonalRecordDisplay(record: recent, now: Fixture.now).isNew)
        #expect(!PersonalRecordDisplay(record: old, now: Fixture.now).isNew)
    }
}
