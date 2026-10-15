import Foundation
import Testing
import Application
import Domain
@testable import Infrastructure

struct FileSleepCacheTests {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sleep-tests-\(UUID().uuidString)", isDirectory: true)
    private var url: URL { directory.appendingPathComponent("SleepNights.json") }
    private var cache: FileSleepCache { FileSleepCache(fileURL: url) }

    private let sleep = CachedSleep(
        generatedAt: Date(timeIntervalSince1970: 1_792_576_800),
        nights: [SleepNight(
            wakeDate: LocalDate(year: 2026, month: 10, day: 21),
            sleepStart: Date(timeIntervalSince1970: 1_792_527_300), wakeTime: Date(timeIntervalSince1970: 1_792_554_600),
            asleepMinutes: 450, deepMinutes: 75, coreMinutes: 275, remMinutes: 100, unspecifiedMinutes: 0,
            awakeMinutes: 5, timeInBedMinutes: 455, hasStages: true, sourceLabel: "Apple Watch"
        )]
    )

    private func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func roundTrip() async throws {
        defer { cleanUp() }
        try await cache.save(sleep)
        #expect(await cache.load() == sleep)
    }

    @Test func aMissingFileIsNoCache() async {
        #expect(await cache.load() == nil)
    }

    @Test func aCorruptFileIsNoCache() async throws {
        defer { cleanUp() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ nope".utf8).write(to: url)
        #expect(await cache.load() == nil)
    }

    @Test func anOlderSchemaIsNoCache() async throws {
        defer { cleanUp() }
        try await cache.save(CachedSleep(schemaVersion: 0, generatedAt: sleep.generatedAt, nights: sleep.nights))
        #expect(await cache.load() == nil)
    }
}
