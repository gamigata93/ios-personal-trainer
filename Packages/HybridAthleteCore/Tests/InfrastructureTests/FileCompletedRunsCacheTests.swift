import Foundation
import Testing
import Application
import Domain
@testable import Infrastructure

struct FileCompletedRunsCacheTests {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("runs-tests-\(UUID().uuidString)", isDirectory: true)
    private var url: URL { directory.appendingPathComponent("CompletedRuns.json") }
    private var cache: FileCompletedRunsCache { FileCompletedRunsCache(fileURL: url) }

    private let runs = CachedRuns(
        generatedAt: Date(timeIntervalSince1970: 1_793_178_000),
        planId: "plan-1",
        runs: [CompletedRun(id: "a", localDate: LocalDate(year: 2026, month: 10, day: 12), distanceKm: 5.2, durationSeconds: 1_800)]
    )

    private func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func roundTrip() async throws {
        defer { cleanUp() }
        try await cache.save(runs)
        #expect(await cache.load() == runs)
    }

    @Test func aMissingFileIsNoCache() async {
        #expect(await cache.load() == nil)
    }

    @Test func aCorruptFileIsNoCache() async throws {
        defer { cleanUp() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        #expect(await cache.load() == nil)
    }

    @Test func anOlderSchemaIsNoCache() async throws {
        defer { cleanUp() }
        try await cache.save(CachedRuns(schemaVersion: 0, generatedAt: runs.generatedAt, planId: "plan-1", runs: runs.runs))
        #expect(await cache.load() == nil)
    }
}
