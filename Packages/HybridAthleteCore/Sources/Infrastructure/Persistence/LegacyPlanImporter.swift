import Foundation
import Application
import Domain

/// Moves a plan saved by the old JSON storage into the database, once. Decode
/// only: nothing writes the JSON file any more, and it is never deleted.
/// - No file, or the database already has a plan: the file is left untouched.
/// - Imported: the plan is inserted in one transaction (each session's original
///   date is its date, nothing missed), then the file is renamed
///   "TrainingPlan.json.imported".
/// - Unreadable or another schema version: renamed "TrainingPlan.json.corrupt-<timestamp>"
///   and ignored.
/// - The save fails: the file stays as it is, the app starts without a plan,
///   and the next launch tries again.
/// Nothing is ever logged.
public struct LegacyPlanImporter: Sendable {
    public enum Outcome: Sendable, Equatable {
        case noLegacyFile
        case databaseHasPlan
        case imported
        case corrupt
        case failed
    }

    /// The old FilePlanRepository's file name in Application Support.
    public static let legacyFileName = "TrainingPlan.json"

    private let fileURL: URL?
    private let plans: any PlanRepository
    private let clock: any Clock

    public init(plans: any PlanRepository, clock: any Clock) {
        let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
        self.init(fileURL: directory?.appendingPathComponent(Self.legacyFileName, isDirectory: false), plans: plans, clock: clock)
    }

    /// A legacy file at a specific location. Used by tests.
    public init(fileURL: URL?, plans: any PlanRepository, clock: any Clock) {
        self.fileURL = fileURL
        self.plans = plans
        self.clock = clock
    }

    @discardableResult
    public func run() async -> Outcome {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return .noLegacyFile }
        if await plans.hasActivePlan() { return .databaseHasPlan }
        // Unreadable right now (e.g. still protected): try again next launch.
        guard let data = try? Data(contentsOf: fileURL) else { return .failed }
        guard
            let header = try? Self.decoder.decode(Header.self, from: data),
            header.schemaVersion == 1,
            let plan = try? Self.decoder.decode(TrainingPlan.self, from: data)
        else {
            rename(fileURL, suffix: "corrupt-\(stamp())")
            return .corrupt
        }
        do {
            try await plans.save(plan)
        } catch {
            return .failed
        }
        rename(fileURL, suffix: "imported")
        return .imported
    }

    /// "TrainingPlan.json.<suffix>", with "-2", "-3"... when that name is taken.
    private func rename(_ url: URL, suffix: String) {
        let directory = url.deletingLastPathComponent()
        let base = "\(url.lastPathComponent).\(suffix)"
        var target = directory.appendingPathComponent(base, isDirectory: false)
        var attempt = 1
        while FileManager.default.fileExists(atPath: target.path) {
            attempt += 1
            target = directory.appendingPathComponent("\(base)-\(attempt)", isDirectory: false)
        }
        try? FileManager.default.moveItem(at: url, to: target)
    }

    /// "20261028-070000" in UTC.
    private func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: clock.now())
    }

    private struct Header: Decodable {
        let schemaVersion: Int
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
