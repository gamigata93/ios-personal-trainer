import Foundation

/// Tunable numbers for plan progress. A proposal: confirm before changing.
public enum PlanProgressRules {
    /// A run completes a session when it covers at least this share of the
    /// planned distance on the same local day. Exactly 60% counts.
    public static let matchShare = 0.6
    /// Absorbs floating-point noise so a run of exactly 60% is never rejected.
    static let matchTolerance = 1e-9
}
