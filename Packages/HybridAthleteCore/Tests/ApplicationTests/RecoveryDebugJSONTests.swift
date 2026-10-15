#if DEBUG
import Foundation
import Testing
@testable import Application
import Domain

struct RecoveryDebugJSONTests {
    private typealias T = RefreshRecoveryTests

    @Test func theExportHasEveryPart() async throws {
        let health = FakeHealthDataSource()
        await health.set(hrv: .success(T.hrvSamples(T.day(10, 21), mean: 58) + T.hrvSamples(T.day(10, 20), mean: 60, source: "Oura")))
        await health.set(restingHR: .success([T.restingSample(T.day(10, 21), 49)]))
        let use = RefreshRecovery(health: health, cache: FakeRecoveryCache(), clock: FakeClock(T.now), calendar: T.calendar)
        let hrv = await use.refreshHRV(sleepNights: [])
        let resting = await use.refreshRestingHR()

        let json = RecoveryDebugJSON.string(hrv: hrv.read, restingHr: resting.read, sdkHasRmssdType: true)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(Set(object.keys) == [
            "generatedAt", "timeZone", "window", "sourcesInWindow", "hrvNights", "restingHrDays",
            "shownHrv", "shownRestingHr", "ignored", "sdkHasRmssdType",
        ])
        let sources = try #require(object["sourcesInWindow"] as? [String: [String: Int]])
        #expect(sources["hrv"] == ["Apple Watch": 2, "Oura": 2])
        #expect(sources["restingHr"] == ["Apple Watch": 1])
        let shown = try #require(object["shownHrv"] as? [String: Any])
        #expect(shown["wakeDate"] as? String == "2026-10-21")
        #expect(shown["windowKind"] as? String == "overnightFallback")
        #expect((shown["samples"] as? [Any])?.count == 2)
        #expect(object["sdkHasRmssdType"] as? Bool == true)
    }
}
#endif
