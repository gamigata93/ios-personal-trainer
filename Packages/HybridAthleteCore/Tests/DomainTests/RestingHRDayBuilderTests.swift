import Foundation
import Testing
@testable import Domain

struct RestingHRDayBuilderTests {
    private typealias F = SleepFixtures

    private func sample(_ date: String, _ time: String, _ bpm: Double, source: String = "Apple Watch") -> RestingHRSample {
        RestingHRSample(endDate: F.local(date, time), bpm: bpm, source: source)
    }

    @Test func theDateIsTheLocalDateOfTheEnd() throws {
        // 21:30Z on 21 Oct is local 00:30 on 22 Oct.
        let end = try #require(ISO8601DateFormatter().date(from: "2026-10-21T21:30:00Z"))
        let days = RestingHRDayBuilder.build([RestingHRSample(endDate: end, bpm: 50, source: "Apple Watch")], calendar: F.calendar).days
        #expect(days.map(\.date) == [F.day(10, 22)])
    }

    @Test func theLatestWatchSampleOfTheDayWins() {
        let days = RestingHRDayBuilder.build([
            sample("2026-10-21", "18:50", 52),
            sample("2026-10-21", "07:30", 49),
        ], calendar: F.calendar).days
        #expect(days == [RestingHRDay(date: F.day(10, 21), bpm: 52, sourceLabel: "Apple Watch")])
    }

    @Test func theWatchBeatsAnotherSourceOnTheSameDay() {
        let days = RestingHRDayBuilder.build([
            sample("2026-10-21", "07:30", 49),
            sample("2026-10-21", "12:00", 45, source: "Oura"),
            sample("2026-10-21", "20:00", 46, source: "Oura"),
        ], calendar: F.calendar).days
        #expect(days.map(\.sourceLabel) == ["Apple Watch"])
        #expect(days.map(\.bpm) == [49])
    }

    @Test func withoutTheWatchMostSamplesThenAlphabetical() {
        let most = RestingHRDayBuilder.build([
            sample("2026-10-21", "07:30", 60, source: "Whoop"),
            sample("2026-10-21", "08:30", 61, source: "Whoop"),
            sample("2026-10-21", "09:30", 45, source: "Oura"),
        ], calendar: F.calendar).days
        #expect(most.map(\.sourceLabel) == ["Whoop"])
        #expect(most.map(\.bpm) == [61])

        let tie = RestingHRDayBuilder.build([
            sample("2026-10-21", "07:30", 60, source: "Whoop"),
            sample("2026-10-21", "09:30", 45, source: "Oura"),
        ], calendar: F.calendar).days
        #expect(tie.map(\.sourceLabel) == ["Oura"])
    }
}
