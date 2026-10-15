#if DEBUG
import Foundation
import Testing
import Application
import Domain

struct HealthSnapshotJSONTests {
    /// 365 days after the Unix epoch is 1971-01-01T00:00:00Z.
    private let generatedAt = Date(timeIntervalSince1970: 365 * 86_400)

    private var emptySnapshot: HealthSnapshot {
        HealthSnapshot(
            generatedAt: generatedAt,
            profile: .unread(.locked),
            vo2Max: .unread(.emptyOrNotAllowed),
            restingHeartRate: .unread(.emptyOrNotAllowed),
            runHeartRate: .unread(.error),
            workouts: .unread(.ok),
            personalRecords: .unread(.ok)
        )
    }

    private func object(_ json: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test func topLevelKeysAreSorted() throws {
        let json = HealthSnapshotJSON.string(from: emptySnapshot)
        let order = ["generatedAt", "personalRecords", "profile", "restingHeartRate", "runHeartRate", "vo2Max", "workouts"]
        let positions = try order.map { key in
            try #require(json.range(of: "\"\(key)\"")).lowerBound
        }
        #expect(positions == positions.sorted())
    }

    @Test func datesAreISO8601InUTC() throws {
        let json = HealthSnapshotJSON.string(from: emptySnapshot)
        #expect(try object(json)["generatedAt"] as? String == "1971-01-01T00:00:00Z")
    }

    @Test func unknownValuesAreExplicitNulls() throws {
        let root = try object(HealthSnapshotJSON.string(from: emptySnapshot))
        let profile = try #require(root["profile"] as? [String: Any])
        let vo2Max = try #require(root["vo2Max"] as? [String: Any])
        let resting = try #require(root["restingHeartRate"] as? [String: Any])
        let run = try #require(root["runHeartRate"] as? [String: Any])

        #expect(profile["ageYears"] is NSNull)
        #expect(profile["biologicalSex"] is NSNull)
        #expect(vo2Max["latest"] is NSNull)
        #expect(resting["average30Days"] is NSNull)
        #expect(run["averageBpm"] is NSNull)
        #expect(profile["status"] as? String == "locked")
        #expect(run["windowDays"] as? Int == 90)
    }

    @Test func workoutFieldsKeepNullsAndRecordsMatchTheShape() throws {
        let run = FakeHealthDataSource.run(id: "w1", meters: 5_100, seconds: 1_530, heartRate: nil)
        let record = PersonalRecord(
            distance: .fiveK, timeSeconds: 1_500, actualDistanceMeters: 5_100, timeIsNormalized: true,
            date: generatedAt, workoutId: "w1", isNew: true
        )
        let snapshot = HealthSnapshot(
            generatedAt: generatedAt,
            profile: .unread(.ok),
            vo2Max: .unread(.ok),
            restingHeartRate: .unread(.ok),
            runHeartRate: .unread(.ok),
            workouts: .summarizing([run]),
            personalRecords: PersonalRecordsSection(status: .ok, items: [record])
        )

        let root = try object(HealthSnapshotJSON.string(from: snapshot))
        let workouts = try #require(root["workouts"] as? [String: Any])
        let latest = try #require((workouts["latest"] as? [[String: Any]])?.first)
        #expect(latest["averageHeartRate"] is NSNull)
        #expect(latest["elevationAscendedMeters"] is NSNull)
        #expect(latest["distanceMeters"] as? Double == 5_100)
        #expect(latest["hasRoute"] as? Bool == true)
        #expect(workouts["bySource"] as? [String: Int] == ["WorkOutdoors": 1])

        let item = try #require(((root["personalRecords"] as? [String: Any])?["items"] as? [[String: Any]])?.first)
        #expect(item["distance"] as? String == "5K")
        #expect(item["targetMeters"] as? Double == 5_000)
        #expect(item["paceSecondsPerKm"] as? Double == 300)
        #expect(item["date"] as? String == "1971-01-01T00:00:00Z")
    }
}
#endif
