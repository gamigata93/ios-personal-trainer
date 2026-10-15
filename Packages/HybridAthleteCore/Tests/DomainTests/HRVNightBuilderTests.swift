import Foundation
import Testing
@testable import Domain

/// Hand-calculated nightly HRV in UTC+3.
struct HRVNightBuilderTests {
    private typealias F = SleepFixtures

    private func hrv(_ date: String, _ time: String, _ ms: Double, source: String = "Apple Watch") -> HRVSample {
        HRVSample(date: F.local(date, time), valueMs: ms, source: source)
    }

    /// Wake Wed 21 Oct 2026, asleep 20 Oct 23:15 to 21 Oct 06:50.
    private let workedNight = SleepNight(
        wakeDate: LocalDate(year: 2026, month: 10, day: 21),
        sleepStart: SleepFixtures.local("2026-10-20", "23:15"),
        wakeTime: SleepFixtures.local("2026-10-21", "06:50"),
        asleepMinutes: 450, deepMinutes: 75, coreMinutes: 275, remMinutes: 100, unspecifiedMinutes: 0,
        awakeMinutes: 5, timeInBedMinutes: 455, hasStages: true, sourceLabel: "Apple Watch"
    )

    private var workedSamples: [HRVSample] {
        [
            hrv("2026-10-20", "22:50", 70),
            hrv("2026-10-21", "00:30", 52),
            hrv("2026-10-21", "02:10", 60),
            hrv("2026-10-21", "04:20", 64),
            hrv("2026-10-21", "06:10", 56),
            hrv("2026-10-21", "07:40", 48),
        ]
    }

    private func build(_ samples: [HRVSample], nights: [SleepNight]? = nil, today: LocalDate = F.day(10, 21)) -> HRVNightBuilder.Result {
        HRVNightBuilder.build(samples: samples, sleepNights: nights ?? [workedNight], calendar: F.calendar, today: today)
    }

    @Test func theWorkedNightKeepsOnlySamplesInsideTheSleepWindow() throws {
        let result = build(workedSamples)
        let night = try #require(result.nights.first { $0.wakeDate == F.day(10, 21) })
        #expect(night.meanMs == 58.0)
        #expect(night.sampleCount == 4)
        #expect(night.windowKind == .sleep)
        #expect(night.sourceLabel == "Apple Watch")
        #expect(RecoveryFormat.hrvValueText(night.meanMs) == "58")
    }

    @Test func sleepWindowBoundsAreInclusive() throws {
        let result = build([hrv("2026-10-20", "23:15", 50), hrv("2026-10-21", "06:50", 60)])
        let night = try #require(result.nights.first { $0.wakeDate == F.day(10, 21) })
        #expect(night.sampleCount == 2)
        #expect(night.meanMs == 55)
    }

    @Test func oneSampleIsNoNightAndTwoAreANight() {
        let one = build([hrv("2026-10-21", "02:10", 60)])
        #expect(one.nights.isEmpty)
        #expect(one.ignored.tooFewSamples == 1)

        let two = build([hrv("2026-10-21", "02:10", 60), hrv("2026-10-21", "04:20", 64)])
        #expect(two.nights.map(\.sampleCount) == [2])
        #expect(two.ignored.tooFewSamples == 0)
    }

    @Test func theSourceWithMostSamplesWins() {
        let watch = ["00:30", "02:10", "04:20", "06:10"].map { hrv("2026-10-21", $0, 50) }
        let oura = ["00:40", "02:20", "04:30"].map { hrv("2026-10-21", $0, 80, source: "Oura") }
        #expect(build(watch + oura).nights.first?.sourceLabel == "Apple Watch")
        #expect(build(watch + oura).nights.first?.meanMs == 50)

        // More Oura samples: Oura wins, never combined.
        let moreOura = oura + [hrv("2026-10-21", "05:00", 80, source: "Oura"), hrv("2026-10-21", "05:30", 80, source: "Oura")]
        #expect(build(watch + moreOura).nights.first?.sourceLabel == "Oura")
        #expect(build(watch + moreOura).nights.first?.meanMs == 80)
    }

    @Test func equalCountsPreferTheWatchThenTheFirstLabel() {
        let watch = ["00:30", "02:10"].map { hrv("2026-10-21", $0, 50) }
        let oura = ["00:40", "02:20"].map { hrv("2026-10-21", $0, 80, source: "Oura") }
        let whoop = ["00:50", "02:30"].map { hrv("2026-10-21", $0, 90, source: "Whoop") }
        #expect(build(oura + watch).nights.first?.sourceLabel == "Apple Watch")
        #expect(build(whoop + oura).nights.first?.sourceLabel == "Oura")
    }

    @Test func withoutASleepNightTheOvernightFallbackIsUsed() throws {
        let samples = [
            hrv("2026-10-22", "00:00", 50),
            hrv("2026-10-22", "07:59", 70),
            hrv("2026-10-22", "08:00", 99),
        ]
        let result = build(samples, nights: [workedNight], today: F.day(10, 22))
        let night = try #require(result.nights.first { $0.wakeDate == F.day(10, 22) })
        #expect(night.windowKind == .overnightFallback)
        #expect(night.sampleCount == 2)
        #expect(night.meanMs == 60)
    }

    @Test func midnightUTCPlusThreeBelongsToTheNextDay() throws {
        // 21:00Z on 21 Oct is local 00:00 on 22 Oct.
        let utc = try #require(ISO8601DateFormatter().date(from: "2026-10-21T21:00:00Z"))
        let samples = [HRVSample(date: utc, valueMs: 40, source: "Apple Watch"), hrv("2026-10-22", "03:00", 60)]
        let result = build(samples, nights: [], today: F.day(10, 22))
        #expect(result.nights.map(\.wakeDate) == [F.day(10, 22)])
        #expect(result.nights.first?.meanMs == 50)
    }

    @Test func aRealSleepWindowIsNeverReplacedByTheFallback() throws {
        // Inside 00:00 to 08:00 but after waking at 06:50: not part of the night.
        let samples = workedSamples + [hrv("2026-10-21", "07:00", 10), hrv("2026-10-21", "07:30", 10)]
        let night = try #require(build(samples).nights.first { $0.wakeDate == F.day(10, 21) })
        #expect(night.windowKind == .sleep)
        #expect(night.meanMs == 58.0)
    }
}
