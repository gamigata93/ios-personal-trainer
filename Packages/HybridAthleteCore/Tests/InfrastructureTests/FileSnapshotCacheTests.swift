import Foundation
import Testing
import Application
import Domain
@testable import Infrastructure

struct FileSnapshotCacheTests {
    private let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("snapshot-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("HealthSnapshot.json")

    private static let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private let snapshot = CachedSnapshot(
        generatedAt: date,
        profile: CachedSection(value: ProfileSummary(ageYears: 32, biologicalSex: .male), asOf: date),
        vo2Max: CachedSection(
            value: VO2MaxSummary(
                latest: HealthSample(value: 53.75, unit: "ml/(kg·min)", date: date, sourceName: "Apple Watch"),
                recent: []
            ),
            asOf: date
        ),
        workouts: CachedSection(
            value: WorkoutsSummary(
                totalCount: 375, runCount: 9, runHeartRateAverage: 139.45, personalRecords: [],
                volume: RunningVolume(weeklyKm: 17.69, longestRunKm: 17)
            ),
            asOf: date
        )
    )

    private func cleanUp() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test func roundTrip() async throws {
        defer { cleanUp() }
        let cache = FileSnapshotCache(fileURL: url)
        try await cache.save(snapshot)
        #expect(await FileSnapshotCache(fileURL: url).load() == snapshot)
    }

    @Test func missingFileIsNoCache() async {
        #expect(await FileSnapshotCache(fileURL: url).load() == nil)
    }

    @Test func corruptFileIsNoCache() async throws {
        defer { cleanUp() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        #expect(await FileSnapshotCache(fileURL: url).load() == nil)
    }

    @Test func olderSchemaIsNoCache() async throws {
        defer { cleanUp() }
        let cache = FileSnapshotCache(fileURL: url)
        try await cache.save(CachedSnapshot(schemaVersion: CachedSnapshot.currentSchemaVersion - 1, generatedAt: Self.date))
        #expect(await cache.load() == nil)
    }

    @Test func holdsSummariesOnly() async throws {
        defer { cleanUp() }
        try await FileSnapshotCache(fileURL: url).save(snapshot)
        let text = try String(contentsOf: url, encoding: .utf8)
        for forbidden in ["dateOfBirth", "route", "trackpoint", "\"all\"", "durationSeconds"] {
            #expect(!text.contains(forbidden), "cache file must not contain \(forbidden)")
        }
    }
}
