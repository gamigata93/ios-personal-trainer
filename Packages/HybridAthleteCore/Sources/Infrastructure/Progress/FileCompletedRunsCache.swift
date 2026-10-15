import Foundation
import Application
import Domain

/// Keeps the completed-run summaries in one JSON file in Application Support,
/// protected until the user first unlocks the phone after a restart. A missing,
/// corrupt or older-schema file reads as no cache. Nothing is ever logged.
public actor FileCompletedRunsCache: CompletedRunsCache {
    public static let defaultFileName = "CompletedRuns.json"

    private let fileURL: URL?

    /// The file in this app's Application Support directory.
    public init(fileName: String = FileCompletedRunsCache.defaultFileName) {
        let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        self.fileURL = directory?.appendingPathComponent(fileName, isDirectory: false)
    }

    /// A file at a specific location. Used by tests.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() async -> CachedRuns? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        guard
            let cached = try? Self.decoder.decode(CachedRuns.self, from: data),
            cached.schemaVersion == CachedRuns.currentSchemaVersion
        else {
            return nil
        }
        return cached
    }

    public func save(_ runs: CachedRuns) async throws {
        guard let fileURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(runs)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
