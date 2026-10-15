import Foundation

extension PlanKind: Codable {
    /// Which plan rules a race distance uses. Ultras use the marathon rules for now.
    public static func from(distanceKm: Double) -> PlanKind {
        switch distanceKm {
        case ...6: .fiveK
        case ...12: .tenK
        case ...25: .halfMarathon
        default: .marathon
        }
    }
}

public enum SessionType: String, Sendable, Equatable, Codable, CaseIterable {
    case easy, tempo, threshold, intervals, long
}

public enum PlanPhase: String, Sendable, Equatable, Codable, CaseIterable, Comparable {
    case base, build, peak, taper

    public static func < (lhs: PlanPhase, rhs: PlanPhase) -> Bool {
        (allCases.firstIndex(of: lhs) ?? 0) < (allCases.firstIndex(of: rhs) ?? 0)
    }
}

/// What the user entered on the race setup screen.
public struct RaceSetup: Sendable, Equatable, Codable {
    public let distanceKm: Double
    /// Blank counts as 0.
    public let elevationGainM: Double
    public let raceDate: LocalDate
    public let trainingDays: Set<Weekday>

    public init(distanceKm: Double, elevationGainM: Double, raceDate: LocalDate, trainingDays: Set<Weekday>) {
        self.distanceKm = distanceKm
        self.elevationGainM = elevationGainM
        self.raceDate = raceDate
        self.trainingDays = trainingDays
    }
}

/// The user's current fitness as plan generators see it. The template uses the
/// running numbers; the rest is carried for future generators.
public struct FitnessSummary: Sendable, Equatable, Codable {
    public let weeklyKm: Double
    public let longestRunKm: Double
    public let avgPaceSecPerKm: Double?
    public let vo2Max: Double?
    public let restingHeartRate: Double?
    public let ageYears: Int?

    public init(
        weeklyKm: Double,
        longestRunKm: Double,
        avgPaceSecPerKm: Double?,
        vo2Max: Double? = nil,
        restingHeartRate: Double? = nil,
        ageYears: Int? = nil
    ) {
        self.weeklyKm = weeklyKm
        self.longestRunKm = longestRunKm
        self.avgPaceSecPerKm = avgPaceSecPerKm
        self.vo2Max = vo2Max
        self.restingHeartRate = restingHeartRate
        self.ageYears = ageYears
    }

    public static let none = FitnessSummary(weeklyKm: 0, longestRunKm: 0, avgPaceSecPerKm: nil)
}

/// Where the race came from.
public enum PlanSource: Sendable, Equatable, Codable {
    case suggested(PlanKind)
    case custom
}

/// Everything a plan generator is given.
public struct PlanRequest: Sendable, Equatable {
    public let race: RaceSetup
    public let fitness: FitnessSummary
    public let today: LocalDate
    public let planKind: PlanKind
    public let source: PlanSource
    /// Problems with an earlier attempt, for a model to fix. The template ignores them.
    public let revisionNotes: [String]

    public init(
        race: RaceSetup,
        fitness: FitnessSummary,
        today: LocalDate,
        planKind: PlanKind,
        source: PlanSource,
        revisionNotes: [String] = []
    ) {
        self.race = race
        self.fitness = fitness
        self.today = today
        self.planKind = planKind
        self.source = source
        self.revisionNotes = revisionNotes
    }

    /// The same request with notes for the next attempt.
    public func revised(notes: [String]) -> PlanRequest {
        PlanRequest(race: race, fitness: fitness, today: today, planKind: planKind, source: source, revisionNotes: notes)
    }

    /// Weeks from the plan start to race day.
    public var weekCount: Int { PlanCalendar.weekCount(from: planStart, to: race.raceDate) }

    public var planStart: LocalDate { PlanCalendar.planStart(today: today) }
}

/// One part of a session, such as a warm-up or the main set.
public struct Segment: Sendable, Equatable, Codable {
    public let label: String
    public let detail: String
    public let distanceKm: Double?

    public init(label: String, detail: String, distanceKm: Double?) {
        self.label = label
        self.detail = detail
        self.distanceKm = distanceKm
    }
}

/// One planned run. Its status (completed, missed…) is derived later; only the
/// user's "missed" acknowledgement is stored.
public struct PlannedSession: Sendable, Equatable, Codable {
    /// The ORIGINAL date as "YYYY-MM-DD". It never changes, even when the session
    /// moves, so it is never the current date: use `date` for placement.
    public let id: String
    /// The day the generator put it on.
    public let originalDate: LocalDate
    /// The day it is on now (one session per day at most).
    public let date: LocalDate
    public let type: SessionType
    public let name: String
    public let distanceKm: Double
    public let estimatedMinutes: Int?
    public let effort: String
    public let segments: [Segment]
    public let note: String?
    /// The user marked it as missed. A move clears it.
    public let isMissed: Bool

    /// A freshly generated session: its id and original date are `date`.
    public init(
        date: LocalDate,
        type: SessionType,
        name: String,
        distanceKm: Double,
        estimatedMinutes: Int?,
        effort: String,
        segments: [Segment],
        note: String?
    ) {
        self.init(
            id: date.description, originalDate: date, date: date, type: type, name: name, distanceKm: distanceKm,
            estimatedMinutes: estimatedMinutes, effort: effort, segments: segments, note: note, isMissed: false
        )
    }

    /// A stored session, possibly edited.
    public init(
        id: String,
        originalDate: LocalDate,
        date: LocalDate,
        type: SessionType,
        name: String,
        distanceKm: Double,
        estimatedMinutes: Int?,
        effort: String,
        segments: [Segment],
        note: String?,
        isMissed: Bool
    ) {
        self.id = id
        self.originalDate = originalDate
        self.date = date
        self.type = type
        self.name = name
        self.distanceKm = distanceKm
        self.estimatedMinutes = estimatedMinutes
        self.effort = effort
        self.segments = segments
        self.note = note
        self.isMissed = isMissed
    }

    /// The same session on another day or with another missed flag. Id and content never change.
    public func placed(on date: LocalDate, isMissed: Bool) -> PlannedSession {
        PlannedSession(
            id: id, originalDate: originalDate, date: date, type: type, name: name, distanceKm: distanceKm,
            estimatedMinutes: estimatedMinutes, effort: effort, segments: segments, note: note, isMissed: isMissed
        )
    }

    /// True once an edit put it on another day than the generator did.
    public var isMoved: Bool { date != originalDate }

    private enum CodingKeys: String, CodingKey {
        case id, originalDate, date, type, name, distanceKm, estimatedMinutes, effort, segments, note, isMissed
    }

    /// Plans saved before edits existed have no originalDate or isMissed: the
    /// original date is the date, and nothing is missed.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let date = try container.decode(LocalDate.self, forKey: .date)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            originalDate: try container.decodeIfPresent(LocalDate.self, forKey: .originalDate) ?? date,
            date: date,
            type: try container.decode(SessionType.self, forKey: .type),
            name: try container.decode(String.self, forKey: .name),
            distanceKm: try container.decode(Double.self, forKey: .distanceKm),
            estimatedMinutes: try container.decodeIfPresent(Int.self, forKey: .estimatedMinutes),
            effort: try container.decode(String.self, forKey: .effort),
            segments: try container.decode([Segment].self, forKey: .segments),
            note: try container.decodeIfPresent(String.self, forKey: .note),
            isMissed: try container.decodeIfPresent(Bool.self, forKey: .isMissed) ?? false
        )
    }
}

public struct PlanWeek: Sendable, Equatable, Codable {
    /// 1-based.
    public let index: Int
    /// Always a Monday.
    public let startDate: LocalDate
    public let phase: PlanPhase
    public let targetKm: Double
    public let sessions: [PlannedSession]

    public init(index: Int, startDate: LocalDate, phase: PlanPhase, targetKm: Double, sessions: [PlannedSession]) {
        self.index = index
        self.startDate = startDate
        self.phase = phase
        self.targetKm = targetKm
        self.sessions = sessions
    }

    public var totalKm: Double { sessions.map(\.distanceKm).reduce(0, +) }
}

public struct TrainingPlan: Sendable, Equatable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: String
    public let createdAt: Date
    /// Which generator built it, e.g. "template-v1".
    public let generatedBy: String
    public let planKind: PlanKind
    public let race: RaceSetup
    public let planStart: LocalDate
    public let weeks: [PlanWeek]

    public init(
        schemaVersion: Int = TrainingPlan.currentSchemaVersion,
        id: String,
        createdAt: Date,
        generatedBy: String,
        planKind: PlanKind,
        race: RaceSetup,
        planStart: LocalDate,
        weeks: [PlanWeek]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.generatedBy = generatedBy
        self.planKind = planKind
        self.race = race
        self.planStart = planStart
        self.weeks = weeks
    }

    public var sessions: [PlannedSession] { weeks.flatMap(\.sessions) }

    /// The same plan with `sessions` placed in the week containing each one's
    /// current date, sorted by date. Weeks keep their phase and targetKm as generated.
    public func replacingSessions(_ sessions: [PlannedSession]) -> TrainingPlan {
        let sorted = sessions.sorted { $0.date < $1.date }
        let rebuilt = weeks.enumerated().map { offset, week in
            let isFirst = offset == 0
            let isLast = offset == weeks.count - 1
            let end = week.startDate.adding(days: 7)
            return PlanWeek(
                index: week.index,
                startDate: week.startDate,
                phase: week.phase,
                targetKm: week.targetKm,
                // Dates outside every week (never valid for an edit) stay in the nearest one.
                sessions: sorted.filter { ($0.date >= week.startDate || isFirst) && ($0.date < end || isLast) }
            )
        }
        return TrainingPlan(
            schemaVersion: schemaVersion, id: id, createdAt: createdAt, generatedBy: generatedBy,
            planKind: planKind, race: race, planStart: planStart, weeks: rebuilt
        )
    }

    /// The session with this id (its original date), wherever it is now.
    public func session(id: String) -> PlannedSession? {
        sessions.first { $0.id == id }
    }

    /// The session on this day, if any.
    public func session(on date: LocalDate) -> PlannedSession? {
        sessions.first { $0.date == date }
    }

    /// The same plan with a new identity, as assigned when it is saved.
    public func stamped(id: String, createdAt: Date) -> TrainingPlan {
        TrainingPlan(
            schemaVersion: schemaVersion, id: id, createdAt: createdAt, generatedBy: generatedBy,
            planKind: planKind, race: race, planStart: planStart, weeks: weeks
        )
    }
}

/// Where a plan starts and how many weeks it has.
public enum PlanCalendar {
    /// The first Monday on or after tomorrow.
    public static func planStart(today: LocalDate) -> LocalDate {
        let tomorrow = today.adding(days: 1)
        return tomorrow.adding(days: (7 - tomorrow.weekday.index) % 7)
    }

    /// Days from the plan start to race day, both included.
    public static func inclusiveDays(from planStart: LocalDate, to raceDate: LocalDate) -> Int {
        planStart.days(to: raceDate) + 1
    }

    /// ceil(inclusive days / 7). Weeks run Monday to Sunday; the last holds race day.
    public static func weekCount(from planStart: LocalDate, to raceDate: LocalDate) -> Int {
        let days = inclusiveDays(from: planStart, to: raceDate)
        return days <= 0 ? 0 : (days + 6) / 7
    }
}
