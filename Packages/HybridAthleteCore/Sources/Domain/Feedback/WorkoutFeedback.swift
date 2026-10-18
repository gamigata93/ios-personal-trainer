import Foundation

/// Where something hurts or aches. A fixed list so rules and models read it the same way.
public enum BodyArea: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case knee, calf, shin, achillesAnkle, foot, hip, hamstring, quad, lowerBack, other

    /// "Achilles or ankle".
    public var title: String {
        switch self {
        case .knee: "Knee"
        case .calf: "Calf"
        case .shin: "Shin"
        case .achillesAnkle: "Achilles or ankle"
        case .foot: "Foot"
        case .hip: "Hip"
        case .hamstring: "Hamstring"
        case .quad: "Quad"
        case .lowerBack: "Lower back"
        case .other: "Other"
        }
    }

    /// "calves", for "both calves".
    public var plural: String {
        switch self {
        case .calf: "calves"
        case .foot: "feet"
        case .achillesAnkle: "Achilles or ankles"
        case .lowerBack: "lower back"
        case .other: "other areas"
        default: title.lowercased() + "s"
        }
    }

    /// Below the waist: running and leg strength load it.
    public var isLowerBody: Bool { self != .lowerBack && self != .other }
}

public enum BodySide: String, Sendable, Equatable, Codable, CaseIterable {
    case left, right, both

    public var title: String { rawValue.capitalized }
}

/// The two kinds the template separates, so a rule can tell them apart.
public enum DiscomfortKind: String, Sendable, Equatable, Codable, CaseIterable {
    /// Dull, spread over the muscle, eases once warm: normal training soreness.
    case ache
    /// Sharp or in one spot, in a joint or tendon, or getting worse while running.
    case pain

    public var title: String { rawValue.capitalized }

    public var explanation: String {
        switch self {
        case .ache: "Dull, spread over the muscle, eases once warm."
        case .pain: "Sharp or in one spot, in a joint or tendon, or gets worse as you run."
        }
    }
}

public enum DiscomfortLevel: Int, Sendable, Equatable, Comparable, Codable, CaseIterable {
    case mild = 1, moderate = 2, severe = 3

    /// "Mild".
    public var title: String {
        switch self {
        case .mild: "Mild"
        case .moderate: "Moderate"
        case .severe: "Severe"
        }
    }

    public var explanation: String {
        switch self {
        case .mild: "I noticed it."
        case .moderate: "It bothered me."
        case .severe: "I slowed down, changed my stride or stopped."
        }
    }

    public static func < (lhs: DiscomfortLevel, rhs: DiscomfortLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One area in a report.
public struct AreaReport: Sendable, Equatable, Codable {
    public let area: BodyArea
    /// The typed name when `area` is `.other` ("elbow"); nil otherwise.
    public let otherName: String?
    public let side: BodySide
    public let kind: DiscomfortKind
    public let level: DiscomfortLevel

    public init(area: BodyArea, otherName: String? = nil, side: BodySide, kind: DiscomfortKind, level: DiscomfortLevel) {
        self.area = area
        self.otherName = area == .other ? otherName.map { FeedbackRules.clean($0, limit: FeedbackRules.otherNameMaxLength) } : nil
        self.side = side
        self.kind = kind
        self.level = level
    }

    /// "pain, left knee, moderate".
    public var line: String {
        let typed = otherName.flatMap { $0.isEmpty ? nil : $0 }
        let name = area == .other ? (typed ?? "other area") : (area == .achillesAnkle ? "Achilles or ankle" : area.title.lowercased())
        let plural = area == .other ? (typed.map { "\($0) (both sides)" } ?? "other areas") : area.plural
        let place: String
        if area == .lowerBack {
            place = name
        } else if side == .both {
            place = area == .other && typed != nil ? plural : "both \(plural)"
        } else {
            place = "\(side.rawValue) \(name)"
        }
        return "\(kind.rawValue), \(place), \(level.title.lowercased())"
    }
}

/// Which kind of workout the feedback is about.
public enum FeedbackWorkoutKind: String, Sendable, Equatable, Codable {
    case run, strength
}

/// The user's answer after one Health workout. A skip is stored too, so the
/// workout is never asked about again.
public struct WorkoutFeedback: Sendable, Equatable, Codable {
    public enum Status: String, Sendable, Equatable, Codable {
        /// "Anything bothering you?" No.
        case noIssues
        /// Yes, with at least one area.
        case reported
        /// Closed without answering.
        case skipped
    }

    /// The Health workout UUID.
    public let workoutId: String
    public let workoutKind: FeedbackWorkoutKind
    public let localDate: LocalDate
    public let status: Status
    public let areas: [AreaReport]
    /// Optional, at most `FeedbackRules.noteMaxLength` characters, one line.
    public let note: String?
    public let recordedAt: Date

    public init(
        workoutId: String, workoutKind: FeedbackWorkoutKind, localDate: LocalDate, status: Status, areas: [AreaReport] = [],
        note: String? = nil, recordedAt: Date
    ) {
        self.workoutId = workoutId
        self.workoutKind = workoutKind
        self.localDate = localDate
        self.status = status == .reported && areas.isEmpty ? .noIssues : status
        self.areas = status == .reported ? areas : []
        self.note = note.map { FeedbackRules.clean($0, limit: FeedbackRules.noteMaxLength) }.flatMap { $0.isEmpty ? nil : $0 }
        self.recordedAt = recordedAt
    }

    /// Any area reported as pain.
    public var hasPain: Bool { areas.contains { $0.kind == .pain } }

    public var hasSeverePain: Bool { areas.contains { $0.kind == .pain && $0.level == .severe } }

    /// "Mon 26 Oct run: pain, left knee, moderate; ache, both calves, mild. Note: tight after the hills."
    /// Nil for a skip.
    public var line: String? {
        let head = "\(HomeFormat.shortDate(localDate)) \(workoutKind.rawValue): "
        let body: String
        switch status {
        case .skipped: return nil
        case .noIssues: body = "no issues"
        case .reported: body = areas.map(\.line).joined(separator: "; ")
        }
        return head + body + "." + (note.map { " Note: \($0)" } ?? "")
    }
}

/// Every number behind feedback and when it suggests a plan change. A first draft; edit freely.
public enum FeedbackRules {
    public static let noteMaxLength = 200
    public static let otherNameMaxLength = 30
    /// Workouts from the last this many days (today included) are asked about.
    public static let promptWindowDays = 3
    /// A moderate ache twice in the same area within this many days suggests a change.
    public static let repeatWindowDays = 7
    /// Feedback lines given to a model: from the last this many days.
    public static let linesWindowDays = 14
    public static let maxLines = 8
    public static let severePainMessage = "If sharp pain lasts, check with a professional."

    /// One line, trimmed, at most `limit` characters.
    public static func clean(_ text: String, limit: Int) -> String {
        let oneLine = text.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return String(oneLine.prefix(limit))
    }

    /// Why `new` should lead to a suggested plan change, or nil. Any pain; a severe
    /// ache; or a moderate (or worse) ache in an area that also ached moderately
    /// (or worse) in another workout within `repeatWindowDays`.
    public static func trigger(_ new: WorkoutFeedback, history: [WorkoutFeedback]) -> AdjustmentTrigger? {
        guard new.status == .reported else { return nil }
        if let pain = new.areas.filter({ $0.kind == .pain }).max(by: { $0.level < $1.level }) {
            return AdjustmentTrigger(feedback: new, report: pain, reason: .pain)
        }
        if let severe = new.areas.first(where: { $0.kind == .ache && $0.level == .severe }) {
            return AdjustmentTrigger(feedback: new, report: severe, reason: .severeAche)
        }
        let earlier = history.filter {
            $0.workoutId != new.workoutId && $0.localDate <= new.localDate
                && $0.localDate.days(to: new.localDate) < repeatWindowDays
        }
        for report in new.areas where report.kind == .ache && report.level >= .moderate {
            let repeated = earlier.contains { old in
                old.areas.contains { $0.kind == .ache && $0.level >= .moderate && $0.area == report.area && $0.otherName == report.otherName }
            }
            if repeated { return AdjustmentTrigger(feedback: new, report: report, reason: .repeatedAche) }
        }
        return nil
    }

    /// Lines for a model: feedback from the last `linesWindowDays` before `today`,
    /// newest first, at most `maxLines`; skips leave no line.
    public static func lines(_ feedback: [WorkoutFeedback], today: LocalDate) -> [String] {
        feedback
            .filter { $0.localDate <= today && $0.localDate.days(to: today) < linesWindowDays }
            .sorted { ($0.localDate, $0.recordedAt) > ($1.localDate, $1.recordedAt) }
            .compactMap(\.line)
            .prefix(maxLines)
            .map { $0 }
    }
}

/// What made a plan change worth suggesting.
public struct AdjustmentTrigger: Sendable, Equatable {
    public enum Reason: String, Sendable, Equatable, Codable {
        case pain, severeAche, repeatedAche
    }

    public let feedback: WorkoutFeedback
    /// The report that tripped the rule.
    public let report: AreaReport
    public let reason: Reason

    public init(feedback: WorkoutFeedback, report: AreaReport, reason: Reason) {
        self.feedback = feedback
        self.report = report
        self.reason = reason
    }
}
