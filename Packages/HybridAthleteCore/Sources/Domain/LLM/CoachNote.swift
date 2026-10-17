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

    /// Lower than the recent nights by more than the neutral band.
    public var isWorse: Bool {
        guard let deltaPercent else { return false }
        return MetricTrend.of(delta: deltaPercent, band: RecoveryRules.hrvNeutralPercent) == .down
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

/// Recovery around the run: the night before it (woken on the run's day) and
/// that day's resting heart rate. Each part is nil when missing.
public struct RecoveryFacts: Sendable, Equatable, Codable {
    public let sleep: SleepFact?
    public let hrv: HRVFact?
    public let restingHr: RestingHRFact?

    public init(sleep: SleepFact? = nil, hrv: HRVFact? = nil, restingHr: RestingHRFact? = nil) {
        self.sleep = sleep
        self.hrv = hrv
        self.restingHr = restingHr
    }

    public static let none = RecoveryFacts()
}

/// A post-workout note in four parts plus a headline. Code wrote the facts;
/// a model (or the rules) wrote these words.
public struct CoachNote: Sendable, Equatable, Codable {
    public static let headlineLimit = 60
    public static let howItWentLimit = 320
    public static let versusPlanLimit = 320
    public static let programStatusLimit = 280
    public static let nextStepLimit = 200

    public let headline: String
    public let howItWent: String
    public let versusPlan: String
    public let programStatus: String
    public let nextStep: String

    public init(headline: String, howItWent: String, versusPlan: String, programStatus: String, nextStep: String) {
        self.headline = headline
        self.howItWent = howItWent
        self.versusPlan = versusPlan
        self.programStatus = programStatus
        self.nextStep = nextStep
    }

    /// Every part, in reading order.
    public var parts: [String] { [headline, howItWent, versusPlan, programStatus, nextStep] }

    /// The note as one plain text (Copy note).
    public var plainText: String {
        """
        \(headline)

        How it went: \(howItWent)
        Versus the plan: \(versusPlan)
        The program: \(programStatus)
        Next: \(nextStep)
        """
    }
}

/// Who wrote a stored note.
public enum CoachNoteSource: String, Sendable, Equatable, Codable {
    case model, rules
}

/// Why a rule-based note stands in for a model's. The texts are shown as they are.
public enum CoachNoteFallback: String, Sendable, Equatable, Codable, CaseIterable {
    case claudeNotSetUp, spendLimit, modelUnavailable, guardRejected

    public var message: String {
        switch self {
        case .claudeNotSetUp: "Claude isn't set up. Showing a rule-based note."
        case .spendLimit: "Your spend limit is reached. Showing a rule-based note."
        case .modelUnavailable: "The AI model isn't available right now. Showing a rule-based note."
        case .guardRejected: "The model's note didn't match your data, so a rule-based note is shown."
        }
    }

    /// Stored in the note's flags as "fallback:<case>".
    public var flag: String { "fallback:\(rawValue)" }

    public init?(flags: [String]) {
        guard let match = flags.lazy.compactMap({ flag -> CoachNoteFallback? in
            guard flag.hasPrefix("fallback:") else { return nil }
            return CoachNoteFallback(rawValue: String(flag.dropFirst("fallback:".count)))
        }).first else { return nil }
        self = match
    }
}

/// One stored note: one current note per session, replaced on regenerate.
public struct SavedCoachNote: Sendable, Equatable, Codable {
    /// 2: the four-part note from the workout analysis.
    public static let currentAnalysisVersion = 2
    /// The model tag of a rule-based note.
    public static let rulesTag = "rules-v1"

    public let planId: String
    public let sessionId: String
    /// The Health workout the note is about.
    public let runId: String
    public let createdAt: Date
    public let source: CoachNoteSource
    /// Nil for a rule-based note.
    public let provider: LLMProvider?
    /// The model's id ("onDevice", "anthropic.haiku55"), or "rules-v1".
    public let modelTag: String
    public let note: CoachNote
    public let verdict: WorkoutVerdict
    /// "fallback:<reason>" when a rule-based note replaced a model's.
    public let flags: [String]
    /// SHA-256 of the facts without the program and recovery lines.
    public let inputHash: String
    /// 0...3; nil for a rule-based note.
    public let factsLevel: Int?
    public let analysisVersion: Int

    public init(
        planId: String, sessionId: String, runId: String, createdAt: Date, source: CoachNoteSource, provider: LLMProvider?,
        modelTag: String, note: CoachNote, verdict: WorkoutVerdict, flags: [String] = [], inputHash: String,
        factsLevel: Int?, analysisVersion: Int = SavedCoachNote.currentAnalysisVersion
    ) {
        self.planId = planId
        self.sessionId = sessionId
        self.runId = runId
        self.createdAt = createdAt
        self.source = source
        self.provider = provider
        self.modelTag = modelTag
        self.note = note
        self.verdict = verdict
        self.flags = flags
        self.inputHash = inputHash
        self.factsLevel = factsLevel
        self.analysisVersion = analysisVersion
    }

    public var fallback: CoachNoteFallback? { CoachNoteFallback(flags: flags) }

    /// "Apple on-device", "Apple Private Cloud", "Claude Haiku 5.5" or "rules".
    public var writerName: String {
        if source == .rules { return "rules" }
        switch ModelChoice(id: modelTag) {
        case .onDevice: return "Apple on-device"
        case .privateCloud: return "Apple Private Cloud"
        case .anthropic(let model): return "Claude \(model.displayName)"
        case nil: return modelTag
        }
    }

    /// Stale when the run or the facts changed since it was written.
    public func isStale(runId: String, inputHash: String) -> Bool {
        self.runId != runId || self.inputHash != inputHash
    }
}

/// Which model writes coach notes. Automatic tries Private Cloud Compute, then
/// on-device, then the rules.
public enum CoachModelPreference: Sendable, Equatable, Hashable {
    case automatic
    case model(ModelChoice)
    case ruleBased

    /// "auto", "template", or a model id ("onDevice", "pcc.light", "anthropic.haiku55").
    public var id: String {
        switch self {
        case .automatic: "auto"
        case .ruleBased: "template"
        case .model(let choice): choice.id
        }
    }

    public init?(id: String) {
        switch id {
        case "auto": self = .automatic
        case "template": self = .ruleBased
        default:
            guard let choice = ModelChoice(id: id) else { return nil }
            self = .model(choice)
        }
    }

    /// "Automatic", "Rules", or the model's name.
    public var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .ruleBased: "Rules"
        case .model(let choice): choice.displayName
        }
    }

    /// The models to try, in order, before the rules.
    public var candidates: [ModelChoice] {
        switch self {
        case .automatic: [.privateCloud(reasoning: .light), .onDevice]
        case .model(let choice): [choice]
        case .ruleBased: []
        }
    }
}
