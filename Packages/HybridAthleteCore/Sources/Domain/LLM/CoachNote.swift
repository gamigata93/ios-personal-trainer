import Foundation

/// Last night's sleep against the nights before.
public struct SleepFact: Sendable, Equatable, Codable {
    public let asleepMinutes: Int
    public let deltaPercent: Double?
    public let nightsUsed: Int

    public init(asleepMinutes: Int, deltaPercent: Double?, nightsUsed: Int = SleepRules.baselineNights) {
        self.asleepMinutes = asleepMinutes
        self.deltaPercent = deltaPercent
        self.nightsUsed = nightsUsed
    }
}

/// Last night's HRV against the nights before.
public struct HRVFact: Sendable, Equatable, Codable {
    public let valueMs: Double
    public let deltaPercent: Double?
    public let nightsUsed: Int

    public init(valueMs: Double, deltaPercent: Double?, nightsUsed: Int = RecoveryRules.baselineWindow) {
        self.valueMs = valueMs
        self.deltaPercent = deltaPercent
        self.nightsUsed = nightsUsed
    }
}

/// Today's resting heart rate against the days before.
public struct RestingHRFact: Sendable, Equatable, Codable {
    public let bpm: Double
    public let deltaBpm: Double?
    public let daysUsed: Int

    public init(bpm: Double, deltaBpm: Double?, daysUsed: Int = RecoveryRules.baselineWindow) {
        self.bpm = bpm
        self.deltaBpm = deltaBpm
        self.daysUsed = daysUsed
    }
}

/// The facts a coach note may use: summaries only, never routes or workout
/// lists. Anything missing stays nil and is left out of the prompt.
public struct CoachNoteRequest: Sendable, Equatable, Codable {
    public let sessionName: String
    public let sessionType: SessionType
    public let status: SessionStatus
    public let plannedKm: Double
    public let doneKm: Double?
    public let doneDurationSeconds: Double?
    public let paceSecPerKm: Int?
    public let weekIndex: Int?
    public let weeksTotal: Int?
    public let phase: PlanPhase?
    public let daysToRace: Int?
    public let sleep: SleepFact?
    public let hrv: HRVFact?
    public let restingHr: RestingHRFact?
    /// The consolidated athlete profile; empty for now.
    public let athleteSummary: String?

    public init(
        sessionName: String,
        sessionType: SessionType,
        status: SessionStatus,
        plannedKm: Double,
        doneKm: Double? = nil,
        doneDurationSeconds: Double? = nil,
        paceSecPerKm: Int? = nil,
        weekIndex: Int? = nil,
        weeksTotal: Int? = nil,
        phase: PlanPhase? = nil,
        daysToRace: Int? = nil,
        sleep: SleepFact? = nil,
        hrv: HRVFact? = nil,
        restingHr: RestingHRFact? = nil,
        athleteSummary: String? = nil
    ) {
        self.sessionName = sessionName
        self.sessionType = sessionType
        self.status = status
        self.plannedKm = plannedKm
        self.doneKm = doneKm
        self.doneDurationSeconds = doneDurationSeconds
        self.paceSecPerKm = paceSecPerKm
        self.weekIndex = weekIndex
        self.weeksTotal = weeksTotal
        self.phase = phase
        self.daysToRace = daysToRace
        self.sleep = sleep
        self.hrv = hrv
        self.restingHr = restingHr
        self.athleteSummary = athleteSummary
    }

    /// The Lab's fixed sample: a long run planned 10.0 km, done 7.0 km in 42:00,
    /// week 2 of 8, base phase, 44 days to race; sleep 7h 30m +7%, HRV 58 ms −6%,
    /// resting heart rate 49 bpm about the same.
    public static let sampleShortRun = CoachNoteRequest(
        sessionName: "Long run",
        sessionType: .long,
        status: .completed,
        plannedKm: 10,
        doneKm: 7,
        doneDurationSeconds: 2_520,
        paceSecPerKm: 360,
        weekIndex: 2,
        weeksTotal: 8,
        phase: .base,
        daysToRace: 44,
        sleep: SleepFact(asleepMinutes: 450, deltaPercent: 7),
        hrv: HRVFact(valueMs: 58, deltaPercent: -6),
        restingHr: RestingHRFact(bpm: 49, deltaBpm: 0.5)
    )
}

/// A short note about one session.
public struct CoachNote: Sendable, Equatable, Codable {
    public static let headlineLimit = 60
    public static let observationLimit = 240
    public static let nextStepLimit = 160

    public let headline: String
    public let observation: String
    public let nextStep: String

    public init(headline: String, observation: String, nextStep: String) {
        self.headline = headline
        self.observation = observation
        self.nextStep = nextStep
    }
}

/// A soft problem with a note. Shown, never blocking.
public enum CoachNoteFlag: Sendable, Equatable {
    case tooLong(field: String, limit: Int)
    /// Numbers in the note that are not in the facts, as written ("9.5").
    case unsupportedNumbers([String])

    /// "Observation longer than 240 characters", "Numbers not in the facts: 9.5".
    public var message: String {
        switch self {
        case .tooLong(let field, let limit): "\(field) longer than \(limit) characters"
        case .unsupportedNumbers(let numbers): "Numbers not in the facts: \(numbers.joined(separator: ", "))"
        }
    }
}

/// Checks a note against its limits and the facts it was given. Pure.
public enum CoachNoteValidator {
    /// A note number matches a fact number within this.
    public static let numberTolerance = 0.05

    public static func flags(_ note: CoachNote, facts: String) -> [CoachNoteFlag] {
        var flags: [CoachNoteFlag] = []
        if note.headline.count > CoachNote.headlineLimit { flags.append(.tooLong(field: "Headline", limit: CoachNote.headlineLimit)) }
        if note.observation.count > CoachNote.observationLimit { flags.append(.tooLong(field: "Observation", limit: CoachNote.observationLimit)) }
        if note.nextStep.count > CoachNote.nextStepLimit { flags.append(.tooLong(field: "Next step", limit: CoachNote.nextStepLimit)) }
        let unsupported = unsupportedNumbers(in: [note.headline, note.observation, note.nextStep].joined(separator: "\n"), facts: facts)
        if !unsupported.isEmpty { flags.append(.unsupportedNumbers(unsupported)) }
        return flags
    }

    /// Digit groups with an optional decimal part that are not within
    /// ±`numberTolerance` of a number in `facts`, in order, without repeats.
    public static func unsupportedNumbers(in text: String, facts: String) -> [String] {
        let known = numbers(in: facts).compactMap(Double.init)
        var seen: Set<String> = []
        return numbers(in: text).filter { token in
            guard let value = Double(token) else { return false }
            let supported = known.contains { abs($0 - value) <= numberTolerance + 1e-9 }
            return !supported && seen.insert(token).inserted
        }
    }

    /// "7.0", "10", "6", "00" from "7.0 of 10 at 6:00".
    static func numbers(in text: String) -> [String] {
        text.matches(of: /\d+(?:\.\d+)?/).map { String($0.output) }
    }
}
