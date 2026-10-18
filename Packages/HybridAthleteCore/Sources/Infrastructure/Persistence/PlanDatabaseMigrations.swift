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
        // One current coach note per session (v3 had not shipped, so the v2 note's
        // columns are folded in here). Prompts and raw outputs are never stored:
        // only the note's own fields. observation holds "how it went".
        migrator.registerMigration("v3_coach_note") { db in
            try db.execute(sql: """
                CREATE TABLE coach_note (
                    planId TEXT NOT NULL,
                    sessionId TEXT NOT NULL,
                    runId TEXT NOT NULL,
                    createdAt TEXT NOT NULL,
                    source TEXT NOT NULL,
                    provider TEXT NULL,
                    modelTag TEXT NOT NULL,
                    headline TEXT NOT NULL,
                    observation TEXT NOT NULL,
                    versusPlan TEXT NULL,
                    programStatus TEXT NULL,
                    nextStep TEXT NOT NULL,
                    verdict TEXT NOT NULL,
                    flags TEXT NOT NULL,
                    inputHash TEXT NOT NULL,
                    analysisVersion INTEGER NOT NULL DEFAULT 1,
                    factsLevel INTEGER NULL,
                    PRIMARY KEY (planId, sessionId),
                    FOREIGN KEY (planId, sessionId) REFERENCES plan_session(planId, id) ON DELETE CASCADE
                );
                """)
        }
        // Derived analysis per Health workout (summaries only, no coordinates or
        // sample timestamps). Kept when a plan is deleted.
        migrator.registerMigration("v4_workout_analysis") { db in
            try db.execute(sql: """
                CREATE TABLE workout_analysis (
                    runId TEXT PRIMARY KEY NOT NULL,
                    computedAt TEXT NOT NULL,
                    schemaVersion INTEGER NOT NULL,
                    json TEXT NOT NULL
                );
                """)
        }
        // Strength sessions: like plan_session, one a day, id "strength-<original date>".
        migrator.registerMigration("v5_plan_strength") { db in
            try db.execute(sql: """
                CREATE TABLE plan_strength (
                    planId TEXT NOT NULL REFERENCES plan(id) ON DELETE CASCADE,
                    id TEXT NOT NULL,
                    originalDate TEXT NOT NULL,
                    date TEXT NOT NULL,
                    focus TEXT NOT NULL,
                    variant TEXT NOT NULL,
                    minutes INTEGER NOT NULL,
                    effort TEXT NOT NULL,
                    isMissed INTEGER NOT NULL,
                    PRIMARY KEY (planId, id),
                    UNIQUE (planId, date)
                );
                CREATE TABLE plan_strength_exercise (
                    planId TEXT NOT NULL REFERENCES plan(id) ON DELETE CASCADE,
                    strengthId TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    name TEXT NOT NULL,
                    sets INTEGER NOT NULL,
                    reps INTEGER NULL,
                    seconds INTEGER NULL,
                    perSide INTEGER NOT NULL,
                    equipment TEXT NOT NULL,
                    howTo TEXT NOT NULL,
                    PRIMARY KEY (planId, strengthId, position)
                );
                """)
        }
        // The user's after-workout feedback, one row per Health workout (a skip is a
        // row too, so it is never asked again). Kept when a plan is deleted.
        migrator.registerMigration("v6_workout_feedback") { db in
            try db.execute(sql: """
                CREATE TABLE workout_feedback (
                    workoutId TEXT PRIMARY KEY NOT NULL,
                    workoutKind TEXT NOT NULL,
                    localDate TEXT NOT NULL,
                    status TEXT NOT NULL,
                    areas TEXT NOT NULL,
                    note TEXT NULL,
                    recordedAt TEXT NOT NULL
                );
                CREATE INDEX workout_feedback_localDate ON workout_feedback(localDate);
                """)
        }
        // Suggested plan changes after feedback: pending until applied or dismissed.
        // The payload holds the sessions before and after, so Undo can restore them.
        migrator.registerMigration("v7_plan_adjustment") { db in
            try db.execute(sql: """
                CREATE TABLE plan_adjustment (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    planId TEXT NOT NULL REFERENCES plan(id) ON DELETE CASCADE,
                    createdAt TEXT NOT NULL,
                    status TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    decidedAt TEXT NULL
                );
                CREATE INDEX plan_adjustment_planId ON plan_adjustment(planId);
                """)
        }
        return migrator
    }
}
