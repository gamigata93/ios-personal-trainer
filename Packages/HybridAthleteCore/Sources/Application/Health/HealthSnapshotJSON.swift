#if DEBUG
import Foundation
import Domain

/// DEBUG only. Turns a snapshot into the pretty-printed JSON for the raw-data sheet:
/// sorted keys, ISO-8601 dates in UTC, and an explicit `null` for every unknown.
public enum HealthSnapshotJSON {
    public static func string(from snapshot: HealthSnapshot) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard
            let data = try? encoder.encode(JSONValue(snapshot)),
            let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }
}

/// A JSON tree that keeps nulls (synthesized Codable drops nil keys).
private enum JSONValue: Encodable {
    case null
    case bool(Bool)
    case int(Int)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    // MARK: Leaves

    static func number(_ value: Double?) -> JSONValue {
        guard let value, value.isFinite else { return .null }
        return .number(value)
    }

    static func int(_ value: Int?) -> JSONValue {
        value.map(JSONValue.int) ?? .null
    }

    static func string(_ value: String?) -> JSONValue {
        value.map(JSONValue.string) ?? .null
    }

    static func bool(_ value: Bool?) -> JSONValue {
        value.map(JSONValue.bool) ?? .null
    }

    static func date(_ value: Date?) -> JSONValue {
        guard let value else { return .null }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return .string(formatter.string(from: value))
    }

    // MARK: Snapshot

    init(_ snapshot: HealthSnapshot) {
        self = .object([
            "generatedAt": .date(snapshot.generatedAt),
            "profile": .object([
                "status": .string(snapshot.profile.status.rawValue),
                "ageYears": .int(snapshot.profile.ageYears),
                "biologicalSex": .string(snapshot.profile.biologicalSex?.rawValue),
            ]),
            "vo2Max": .object([
                "status": .string(snapshot.vo2Max.status.rawValue),
                "latest": .sample(snapshot.vo2Max.latest),
                "recent": .array(snapshot.vo2Max.recent.map { .sample($0) }),
            ]),
            "restingHeartRate": .object([
                "status": .string(snapshot.restingHeartRate.status.rawValue),
                "latest": .sample(snapshot.restingHeartRate.latest),
                "average30Days": .number(snapshot.restingHeartRate.average30Days),
                "sampleCount30Days": .int(snapshot.restingHeartRate.sampleCount30Days),
            ]),
            "runHeartRate": .object([
                "status": .string(snapshot.runHeartRate.status.rawValue),
                "averageBpm": .number(snapshot.runHeartRate.averageBpm),
                "workoutCount": .int(snapshot.runHeartRate.workoutCount),
                "windowDays": .int(snapshot.runHeartRate.windowDays),
            ]),
            "workouts": .object([
                "status": .string(snapshot.workouts.status.rawValue),
                "total": .int(snapshot.workouts.total),
                "bySource": .object(snapshot.workouts.bySource.mapValues { .int($0) }),
                "byActivityType": .object(snapshot.workouts.byActivityType.mapValues { .int($0) }),
                "latest": .array(snapshot.workouts.latest.map { .workout($0) }),
            ]),
            "personalRecords": .object([
                "status": .string(snapshot.personalRecords.status.rawValue),
                "items": .array(snapshot.personalRecords.items.map { .record($0) }),
            ]),
        ])
    }

    private static func sample(_ sample: HealthSample?) -> JSONValue {
        guard let sample else { return .null }
        return .object([
            "value": .number(sample.value),
            "unit": .string(sample.unit),
            "date": .date(sample.date),
            "sourceName": .string(sample.sourceName),
        ])
    }

    private static func workout(_ workout: WorkoutSummary) -> JSONValue {
        .object([
            "id": .string(workout.id),
            "activityType": .string(workout.activityType.rawValue),
            "sourceName": .string(workout.sourceName),
            "start": .date(workout.start),
            "end": .date(workout.end),
            "durationSeconds": .number(workout.durationSeconds),
            "distanceMeters": .number(workout.distanceMeters),
            "averageHeartRate": .number(workout.averageHeartRate),
            "maxHeartRate": .number(workout.maxHeartRate),
            "activeEnergyKilocalories": .number(workout.activeEnergyKilocalories),
            "elevationAscendedMeters": .number(workout.elevationAscendedMeters),
            "hasRoute": .bool(workout.hasRoute),
        ])
    }

    private static func record(_ record: PersonalRecord) -> JSONValue {
        .object([
            "distance": .string(record.distance.rawValue),
            "targetMeters": .number(record.targetMeters),
            "timeSeconds": .number(record.timeSeconds),
            "paceSecondsPerKm": .number(record.paceSecondsPerKm),
            "actualDistanceMeters": .number(record.actualDistanceMeters),
            "timeIsNormalized": .bool(record.timeIsNormalized),
            "date": .date(record.date),
            "workoutId": .string(record.workoutId),
            "isNew": .bool(record.isNew),
        ])
    }
}
#endif
