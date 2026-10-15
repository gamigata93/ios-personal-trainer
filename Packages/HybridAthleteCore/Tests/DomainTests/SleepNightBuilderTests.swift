import Foundation
import Testing
@testable import Domain

struct SleepNightBuilderTests {
    private typealias F = SleepFixtures

    private func build(_ segments: [SleepSegment]) -> SleepNightBuilder.Result {
        SleepNightBuilder.build(segments, calendar: F.calendar)
    }

    @Test func theWorkedNight() throws {
        let result = build(F.workedNight())
        let night = try #require(result.nights.first)
        #expect(result.nights.count == 1)
        #expect(night.wakeDate == F.day(10, 21))
        #expect(night.sleepStart == F.local("2026-10-20", "23:15"))
        #expect(night.wakeTime == F.local("2026-10-21", "06:50"))
        #expect(night.asleepMinutes == 450)
        #expect(night.coreMinutes == 275)
        #expect(night.deepMinutes == 75)
        #expect(night.remMinutes == 100)
        #expect(night.unspecifiedMinutes == 0)
        #expect(night.awakeMinutes == 5)
        #expect(night.timeInBedMinutes == 455)
        #expect(night.hasStages)
        #expect(night.sourceLabel == "Apple Watch")
        #expect(SleepFormat.durationText(minutes: night.asleepMinutes) == "7h 30m")
    }

    @Test func inBedSamplesAreIgnored() {
        let inBed = F.segment(.inBed, ("2026-10-20", "22:30"), ("2026-10-21", "07:10"), source: "iPhone")
        let result = build(F.workedNight() + [inBed])
        #expect(result.nights == build(F.workedNight()).nights)
        #expect(result.ignored.inBedSegments == 1)
    }

    @Test func overlappingSegmentsCountOnce() {
        let first = F.segment(.core, ("2026-10-20", "23:15"), ("2026-10-21", "00:45"))
        let inside = F.segment(.core, ("2026-10-20", "23:30"), ("2026-10-21", "00:00"))
        #expect(SleepNightBuilder.unionMinutes([first, inside]) == 90)
        #expect(build(F.workedNight() + [inside]).nights.first?.coreMinutes == 275)
        #expect(build(F.workedNight() + [inside]).nights.first?.asleepMinutes == 450)
    }

    @Test func aSixtyMinuteGapKeepsOneSession() {
        let first = F.segment(.core, ("2026-10-20", "22:00"), ("2026-10-21", "00:30"))
        let second = F.segment(.core, ("2026-10-21", "01:30"), ("2026-10-21", "03:30"))
        #expect(SleepNightBuilder.sessions([first, second]).count == 1)
        #expect(build([first, second]).nights.first?.asleepMinutes == 270)
    }

    @Test func aSixtyOneMinuteGapSplitsAndTheLargerWins() {
        let first = F.segment(.core, ("2026-10-20", "22:00"), ("2026-10-21", "00:30")) // 150
        let second = F.segment(.core, ("2026-10-21", "01:31"), ("2026-10-21", "03:31")) // 120
        #expect(SleepNightBuilder.sessions([first, second]).count == 2)
        let result = build([first, second])
        #expect(result.nights.count == 1)
        #expect(result.nights.first?.asleepMinutes == 150)
    }

    @Test func aNapIsIgnored() {
        // 40 min asleep, woke 14:40: inside 09:00 to 20:00.
        let nap = F.segment(.core, ("2026-10-21", "14:00"), ("2026-10-21", "14:40"))
        let result = build(F.workedNight() + [nap])
        #expect(result.nights == build(F.workedNight()).nights)
        #expect(result.ignored.naps == 1)
    }

    @Test func aLongAfternoonSleepIsTooShortNotANap() {
        let afternoon = F.segment(.core, ("2026-10-21", "14:00"), ("2026-10-21", "15:40")) // 100
        let result = build(F.workedNight() + [afternoon])
        #expect(result.ignored.naps == 0)
        #expect(result.ignored.tooShort == 1)
        #expect(result.nights.count == 1)
    }

    @Test func aShortNightIsIgnored() {
        let short = F.segment(.core, ("2026-10-21", "05:00"), ("2026-10-21", "06:40")) // 100
        let result = build([short])
        #expect(result.nights.isEmpty)
        #expect(result.ignored.tooShort == 1)
    }

    // MARK: Sources

    private func unspecified(_ start: String, _ end: String, source: String) -> SleepSegment {
        F.segment(.asleepUnspecified, ("2026-10-20", start), ("2026-10-21", end), source: source)
    }

    @Test func theWatchBeatsAShorterThirdPartyNight() {
        // Zepp 23:20 to 06:30 = 430.
        let result = build(F.workedNight() + [unspecified("23:20", "06:30", source: "Zepp")])
        #expect(result.nights.map(\.sourceLabel) == ["Apple Watch"])
        #expect(result.nights.first?.asleepMinutes == 450)
    }

    @Test func aTieGoesToTheWatch() {
        let result = build([unspecified("23:00", "06:30", source: "Zepp")] + F.workedNight())
        #expect(result.nights.map(\.sourceLabel) == ["Apple Watch"])
    }

    @Test func aTieBetweenThirdPartiesGoesToTheFirstLabel() {
        let result = build([unspecified("23:00", "06:30", source: "Zepp"), unspecified("23:00", "06:30", source: "Oura")])
        #expect(result.nights.map(\.sourceLabel) == ["Oura"])
    }

    @Test func unspecifiedOnlyHasNoStagesButCounts() throws {
        let night = try #require(build([unspecified("23:00", "06:30", source: "Zepp")]).nights.first)
        #expect(night.asleepMinutes == 450)
        #expect(night.unspecifiedMinutes == 450)
        #expect(!night.hasStages)
    }

    // MARK: Wake date

    @Test func wakeDateUsesTheLocalZone() throws {
        let iso = ISO8601DateFormatter()
        let afterMidnight = SleepSegment(
            start: try #require(iso.date(from: "2026-10-20T20:30:00Z")),
            end: try #require(iso.date(from: "2026-10-20T23:30:00Z")), // 02:30 local, 21 Oct
            stage: .core, source: "Apple Watch"
        )
        let beforeMidnight = SleepSegment(
            start: try #require(iso.date(from: "2026-10-20T17:59:00Z")),
            end: try #require(iso.date(from: "2026-10-20T20:59:00Z")), // 23:59 local, 20 Oct
            stage: .core, source: "Apple Watch"
        )
        #expect(build([afterMidnight]).nights.first?.wakeDate == F.day(10, 21))
        #expect(build([beforeMidnight]).nights.first?.wakeDate == F.day(10, 20))
    }
}
