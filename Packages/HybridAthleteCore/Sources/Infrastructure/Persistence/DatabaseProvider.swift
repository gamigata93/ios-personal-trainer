import Foundation
import GRDB

/// Opens the app database: trainer.sqlite in Application Support, protected until
/// the user first unlocks the phone after a restart, with foreign keys on and every
/// migration applied. It holds user data that must not be lost (the plan and its
/// edit log); caches stay JSON files. GRDB types never leave Infrastructure.
public final class DatabaseProvider: Sendable {
    public static let fileName = "trainer.sqlite"

    let writer: any DatabaseWriter

    private init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try PlanDatabaseMigrations.migrator.migrate(writer)
    }

    /// The database file in Application Support.
    public static func onDisk() throws -> DatabaseProvider {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return try onDisk(directory: directory)
    }

    /// The database file in `directory`. Used by tests too.
    public static func onDisk(directory: URL) throws -> DatabaseProvider {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName, isDirectory: false)
        let provider = try DatabaseProvider(writer: DatabaseQueue(path: url.path, configuration: configuration))
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path
        )
        #endif
        return provider
    }

    /// A fresh database in memory: tests, previews and DEBUG `-seedPlan`.
    public static func inMemory() throws -> DatabaseProvider {
        try DatabaseProvider(writer: DatabaseQueue(configuration: configuration))
    }

    private static var configuration: Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        return configuration
    }
}
