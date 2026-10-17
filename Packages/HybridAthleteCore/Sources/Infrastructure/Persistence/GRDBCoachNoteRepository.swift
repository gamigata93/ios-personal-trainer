import Foundation
import GRDB
import Application
import Domain

/// Coach notes in the app database (table coach_note, migration v3_coach_note).
/// One row per session; saving replaces it. Deleting the plan (or the session)
/// deletes its notes. Nothing is ever logged.
public struct GRDBCoachNoteRepository: CoachNoteRepository {
    private let database: DatabaseProvider

    public init(database: DatabaseProvider) {
        self.database = database
    }

    public func note(planId: String, sessionId: String) async throws -> SavedCoachNote? {
        try await database.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM coach_note WHERE planId = ? AND sessionId = ?", arguments: [planId, sessionId])
                .flatMap(Self.note)
        }
    }

    public func save(_ note: SavedCoachNote) async throws {
        let flags = String(data: try JSONEncoder().encode(note.flags), encoding: .utf8) ?? "[]"
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO coach_note (planId, sessionId, runId, createdAt, source, provider, modelTag, headline,
                        observation, versusPlan, programStatus, nextStep, verdict, flags, inputHash, analysisVersion, factsLevel)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    note.planId, note.sessionId, note.runId, GRDBPlanRepository.timestamp(note.createdAt), note.source.rawValue,
                    note.provider?.rawValue, note.modelTag, note.note.headline, note.note.howItWent, note.note.versusPlan,
                    note.note.programStatus, note.note.nextStep, note.verdict.rawValue, flags, note.inputHash,
                    note.analysisVersion, note.factsLevel,
                ]
            )
        }
    }

    public func notes(planId: String) async throws -> [SavedCoachNote] {
        try await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM coach_note WHERE planId = ? ORDER BY sessionId", arguments: [planId])
                .compactMap(Self.note)
        }
    }

    public func delete(planId: String, sessionId: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM coach_note WHERE planId = ? AND sessionId = ?", arguments: [planId, sessionId])
        }
    }

    /// Nil for a row this build cannot read.
    private static func note(_ row: Row) -> SavedCoachNote? {
        guard
            let createdAt = GRDBPlanRepository.date(row["createdAt"]),
            let source = CoachNoteSource(rawValue: row["source"]),
            let verdict = WorkoutVerdict(rawValue: row["verdict"])
        else { return nil }
        let flagsText: String = row["flags"]
        let flags = (try? JSONDecoder().decode([String].self, from: Data(flagsText.utf8))) ?? []
        let provider: String? = row["provider"]
        return SavedCoachNote(
            planId: row["planId"],
            sessionId: row["sessionId"],
            runId: row["runId"],
            createdAt: createdAt,
            source: source,
            provider: provider.flatMap(LLMProvider.init(rawValue:)),
            modelTag: row["modelTag"],
            note: CoachNote(
                headline: row["headline"],
                howItWent: row["observation"],
                versusPlan: row["versusPlan"] ?? "",
                programStatus: row["programStatus"] ?? "",
                nextStep: row["nextStep"]
            ),
            verdict: verdict,
            flags: flags,
            inputHash: row["inputHash"],
            factsLevel: row["factsLevel"],
            analysisVersion: row["analysisVersion"]
        )
    }
}

/// Workout analyses in the app database (table workout_analysis, migration
/// v4_workout_analysis), as the Codable JSON. No coordinates or sample timestamps.
public struct GRDBWorkoutAnalysisRepository: WorkoutAnalysisRepository {
    private let database: DatabaseProvider

    public init(database: DatabaseProvider) {
        self.database = database
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public func analysis(runId: String) async throws -> WorkoutAnalysis? {
        let json = try await database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT json FROM workout_analysis WHERE runId = ?", arguments: [runId])
        }
        return json.flatMap { try? Self.decoder.decode(WorkoutAnalysis.self, from: Data($0.utf8)) }
    }

    public func save(_ analysis: WorkoutAnalysis) async throws {
        let json = String(data: try Self.encoder.encode(analysis), encoding: .utf8) ?? "{}"
        try await database.writer.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO workout_analysis (runId, computedAt, schemaVersion, json) VALUES (?, ?, ?, ?)",
                arguments: [analysis.runId, GRDBPlanRepository.timestamp(analysis.computedAt), analysis.schemaVersion, json]
            )
        }
    }

    public func delete(runId: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM workout_analysis WHERE runId = ?", arguments: [runId])
        }
    }
}
