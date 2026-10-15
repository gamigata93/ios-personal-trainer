import Foundation
import GRDB

/// Named, additive migrations. NEVER edit a shipped migration: every later
/// change is a new one appended below.
enum PlanDatabaseMigrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_plan") { db in
            try db.execute(sql: """
                CREATE TABLE plan (
                    id TEXT PRIMARY KEY NOT NULL,
                    schemaVersion INTEGER NOT NULL,
                    createdAt TEXT NOT NULL,
                    generatedBy TEXT NOT NULL,
                    planKind TEXT NOT NULL,
                    raceDistanceKm REAL NOT NULL,
                    raceElevationM REAL NOT NULL,
                    raceDate TEXT NOT NULL,
                    planStart TEXT NOT NULL,
                    trainingDays TEXT NOT NULL,
                    isActive INTEGER NOT NULL
                );
                CREATE TABLE plan_week (
                    planId TEXT NOT NULL REFERENCES plan(id) ON DELETE CASCADE,
                    idx INTEGER NOT NULL,
                    phase TEXT NOT NULL,
                    startDate TEXT NOT NULL,
                    targetKm REAL NOT NULL,
                    PRIMARY KEY (planId, idx)
                );
                CREATE TABLE plan_session (
                    planId TEXT NOT NULL REFERENCES plan(id) ON DELETE CASCADE,
                    id TEXT NOT NULL,
                    originalDate TEXT NOT NULL,
                    date TEXT NOT NULL,
                    type TEXT NOT NULL,
                    name TEXT NOT NULL,
                    distanceKm REAL NOT NULL,
                    estimatedMinutes INTEGER NULL,
                    effort TEXT NOT NULL,
                    note TEXT NULL,
                    isMissed INTEGER NOT NULL,
                    PRIMARY KEY (planId, id),
                    UNIQUE (planId, date)
                );
                CREATE TABLE plan_segment (
                    planId TEXT NOT NULL REFERENCES plan(id) ON DELETE CASCADE,
                    sessionId TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    label TEXT NOT NULL,
                    detail TEXT NOT NULL,
                    distanceKm REAL NULL,
                    PRIMARY KEY (planId, sessionId, position)
                );
                CREATE TABLE plan_edit (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    planId TEXT NOT NULL REFERENCES plan(id) ON DELETE CASCADE,
                    createdAt TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    undoneAt TEXT NULL
                );
                CREATE INDEX plan_edit_planId ON plan_edit(planId);
                """)
        }
        // One row per model call: token counts and costs. Never prompt or output text.
        migrator.registerMigration("v2_llm_usage") { db in
            try db.execute(sql: """
                CREATE TABLE llm_usage (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    createdAt TEXT NOT NULL,
                    provider TEXT NOT NULL,
                    modelId TEXT NOT NULL,
                    purpose TEXT NOT NULL,
                    success INTEGER NOT NULL,
                    errorKind TEXT NULL,
                    uncachedInput INTEGER NOT NULL,
                    cacheRead INTEGER NOT NULL,
                    cacheWrite INTEGER NOT NULL,
                    output INTEGER NOT NULL,
                    reasoning INTEGER NULL,
                    latencyMs INTEGER NOT NULL,
                    costMicros INTEGER NULL,
                    priceTableVersion TEXT NOT NULL
                );
                CREATE INDEX llm_usage_createdAt ON llm_usage(createdAt);
                """)
        }
        return migrator
    }
}
