import Foundation
import Testing
import Application
import Domain
@testable import Infrastructure

struct FileRecoveryCacheTests {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("recovery-tests-\(UUID().uuidString)", isDirectory: true)
    private var url: URL { directory.appendingPathComponent("Recovery.json") }
    private var cache: FileRecoveryCache { FileRecoveryCache(fileURL: url) }

    private let recovery = CachedRecovery(
        generatedAt: Date(timeIntervalSince1970: 1_792_576_800),
        hrv: [HRVNight(wakeDate: LocalDate(year: 2026, month: 10, day: 21), meanMs: 58.25, sampleCount: 4, windowKind: .sleep, sourceLabel: "Apple Watch")],
        restingHr: [RestingHRDay(date: LocalDate(year: 2026, month: 10, day: 21), bpm: 49, sourceLabel: "Apple Watch")]
    )

    private func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func roundTrip() async throws {
        defer { cleanUp() }
        try await cache.save(recovery)
        #expect(await cache.load() == recovery)
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
        try await cache.save(CachedRecovery(schemaVersion: 0, generatedAt: recovery.generatedAt, hrv: recovery.hrv, restingHr: recovery.restingHr))
        #expect(await cache.load() == nil)
    }
}
