import Foundation

/// Every number behind a session's content (segments, effort, minutes, notes),
/// shared by the template generator and the LLM draft expander.
public enum SessionContentRules {
    /// Sessions this long or longer get the longer warm-up and cool-down.
    public static let longWarmUpFromKm = 6.0
    public static let longWarmUpKm = 1.5
    public static let shortWarmUpKm = 1.0

    public static let thresholdKmPerRep = 1.8
    public static let thresholdReps = 2...5
    public static let thresholdRepMinutes = 8
    public static let thresholdRecoverySeconds = 90

    public static let intervalKmPerRep = 1.2
    public static let intervalReps = 4...10
    public static let intervalRepMeters = 800
    public static let intervalRecoveryMeters = 400

    /// Long runs from the build phase on, this long or longer, finish faster.
    public static let longRunFinishFromKm = 10.0
    public static let longRunFinishKm = 2

    public static let minutesRounding = 5

    /// Hilly races (at least this much climbing) add a climbing note to long runs.
    public static let terrainFromGainM = 300.0
    public static let terrainShare = 0.7
    public static let terrainRoundingM = 10.0
}

/// Turns a day, a type and a distance into a full session: name, effort,
/// segments, estimated minutes and the terrain note. Pure; the template and
/// `PlanDraftExpander` both use it, so an LLM never writes session details.
public enum SessionContentBuilder {
    private typealias Rules = SessionContentRules

    public static func session(
        date: LocalDate,
        type: SessionType,
        distanceKm km: Double,
        phase: PlanPhase,
        kind: PlanKind,
        race: RaceSetup,
        avgPaceSecPerKm: Double?
    ) -> PlannedSession {
        let warmUp = km >= Rules.longWarmUpFromKm ? Rules.longWarmUpKm : Rules.shortWarmUpKm
        let main = max(0, km - 2 * warmUp)
        let warmUpSegment = Segment(label: "Warm-up", detail: "Easy jog", distanceKm: warmUp)
        let coolDownSegment = Segment(label: "Cool-down", detail: "Easy jog", distanceKm: warmUp)
        let isRacePace = type == .tempo && phase == .peak && (kind == .halfMarathon || kind == .marathon)

        let name: String
        let effort: String
        var segments: [Segment]
        var note: String?

        switch type {
        case .easy:
            name = "Easy run"
            effort = "Conversational"
            segments = [Segment(label: "Easy", detail: "Conversational effort", distanceKm: km)]
        case .tempo:
            if isRacePace {
                name = "Race-pace tempo"
                effort = "Race effort"
            } else if phase == .taper {
                name = "Short tempo"
                effort = "Tempo effort"
            } else {
                name = "Tempo run"
                effort = phase == .base ? "Comfortably hard" : "Tempo effort"
            }
            segments = [warmUpSegment, Segment(label: "Tempo", detail: "\(text(main)) km continuous, \(effort.lowercased())", distanceKm: main), coolDownSegment]
        case .threshold:
            let reps = clamp(Int((main / Rules.thresholdKmPerRep).rounded()), Rules.thresholdReps)
            name = "Threshold reps"
            effort = "Threshold"
            segments = [
                warmUpSegment,
                Segment(
                    label: "Threshold",
                    detail: "\(reps) x \(Rules.thresholdRepMinutes) min at threshold, \(Rules.thresholdRecoverySeconds) s jog recovery",
                    distanceKm: main
                ),
                coolDownSegment,
            ]
        case .intervals:
            let reps = clamp(Int((main / Rules.intervalKmPerRep).rounded()), Rules.intervalReps)
            name = "\(Rules.intervalRepMeters) m repeats"
            effort = "Hard but controlled"
            segments = [
                warmUpSegment,
                Segment(label: "Intervals", detail: "\(reps) x \(Rules.intervalRepMeters) m, \(Rules.intervalRecoveryMeters) m jog", distanceKm: main),
                coolDownSegment,
            ]
        case .long:
            name = "Long run"
            effort = "Steady"
            let fromBuild = phase != .base
            let finish = fromBuild && km >= Rules.longRunFinishFromKm
                ? "Steady, last \(Rules.longRunFinishKm) km at moderate effort"
                : "Steady effort"
            segments = [Segment(label: "Long run", detail: finish, distanceKm: km)]
            let gain = race.elevationGainM
            if fromBuild && gain >= Rules.terrainFromGainM {
                let climb = km * (gain / race.distanceKm) * Rules.terrainShare
                let rounded = Int((climb / Rules.terrainRoundingM).rounded() * Rules.terrainRoundingM)
                note = "Include about \(rounded) m of climbing."
            }
        }

        return PlannedSession(
            date: date,
            type: type,
            name: name,
            distanceKm: km,
            estimatedMinutes: minutes(km, pace: avgPaceSecPerKm),
            effort: effort,
            segments: segments,
            note: note
        )
    }

    /// km x pace, to the nearest 5 minutes; `nil` without a pace.
    public static func minutes(_ km: Double, pace: Double?) -> Int? {
        guard let pace, pace > 0 else { return nil }
        let step = Double(Rules.minutesRounding)
        return max(Rules.minutesRounding, Int((km * pace / 60 / step).rounded() * step))
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// "2.5", "3".
    private static func text(_ km: Double) -> String {
        km == km.rounded() ? String(Int(km)) : String(format: "%.1f", km)
    }
}
