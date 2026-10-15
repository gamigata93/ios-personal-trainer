import Foundation
import Domain

/// Every number behind the v1 template plan, in one place.
enum PlanTemplateRules {
    static let generatedBy = "template-v1"

    // MARK: Weekly distance

    /// Week 1 starts at max(baseline weekly km, this).
    static let minimumStartKm = 10.0
    /// Load grows by this factor each week until it reaches the peak target.
    static let weeklyGrowth = 1.10
    /// Every 4th week before the peak is a recovery week at 80% of the week before.
    static let recoveryEvery = 4
    static let recoveryFactor = 0.8
    /// Base gets this share of the weeks that are not peak or taper (at least 1).
    static let baseShareOfRemaining = 0.45
    /// Every weekly and session distance is rounded to this.
    static let roundingKm = 0.5

    static func peakTargetKm(_ kind: PlanKind) -> Double {
        switch kind {
        case .fiveK: 30
        case .tenK: 40
        case .halfMarathon: 55
        case .marathon: 75
        }
    }

    static func taperWeeks(_ kind: PlanKind) -> Int {
        switch kind {
        case .fiveK, .tenK: 1
        case .halfMarathon: 2
        case .marathon: 3
        }
    }

    static func peakWeeks(_ kind: PlanKind) -> Int {
        switch kind {
        case .fiveK, .tenK: 1
        case .halfMarathon, .marathon: 2
        }
    }

    /// Taper weeks as factors of the last peak week's unrounded load.
    static func taperFactors(weeks: Int) -> [Double] {
        switch weeks {
        case 1: [0.6]
        case 2: [0.75, 0.5]
        default: [0.8, 0.65, 0.5]
        }
    }

    // MARK: Sessions

    /// Share of the week for the long run, by sessions that week.
    static func longShare(sessions: Int) -> Double {
        switch sessions {
        case ...2: 0.55
        case 3: 0.40
        case 4: 0.35
        default: 0.32
        }
    }

    /// Share of the week for each quality session, by sessions that week.
    static func qualityShare(sessions: Int) -> Double {
        switch sessions {
        case ...2: 0.45
        case 3: 0.27
        case 4: 0.22
        default: 0.18
        }
    }

    /// Two quality sessions in build and peak weeks from this many sessions.
    static let sessionsForSecondQuality = 4
    static let minimumSessionKm = 3.0
    /// The long run gives distance to short sessions down to this.
    static let minimumLongRunKm = 4.0

    /// Race week: the first session is quality at this share of the week; every
    /// session is capped at a share of the race distance.
    static let raceWeekQualityShare = 0.45
    static let raceWeekCapOfRaceDistance = 0.75

    // Session content (segments, effort, minutes, notes) lives in Domain `SessionContentRules`.
}
