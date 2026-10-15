import Foundation
import Application
import Domain

/// Keeps the cached summaries in one JSON file in Application Support, protected
/// until the user first unlocks the phone after a restart. A missing, corrupt or
/// older-schema file reads as no cache. Nothing is ever logged.
public actor FileSnapshotCache: SnapshotCache {
    public static let defaultFileName = "HealthSnapshot.json"

    private let fileURL: URL?

    /// The file in this app's Application Support directory.
    public init(fileName: String = FileSnapshotCache.defaultFileName) {
        let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        self.fileURL = directory?.appendingPathComponent(fileName, isDirectory: false)
    }

    /// A file at a specific location. Used by tests.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() async -> CachedSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        guard
            let snapshot = try? Self.decoder.decode(CachedSnapshot.self, from: data),
            snapshot.schemaVersion == CachedSnapshot.currentSchemaVersion
        else {
            return nil
        }
        return snapshot
    }

    public func save(_ snapshot: CachedSnapshot) async throws {
        guard let fileURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Deletes the file. Used by DEBUG launch options and tests. Safe from any
    /// thread: it only reads the immutable file location.
    public nonisolated func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
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
