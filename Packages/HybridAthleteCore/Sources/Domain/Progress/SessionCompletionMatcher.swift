import Foundation

/// Pairs completed runs with planned sessions.
public enum SessionCompletionMatcher {
    /// For each session, the runs on the same local day covering at least
    /// `PlanProgressRules.matchShare` of its distance are candidates; the longest
    /// wins. A run matches at most one session, and runs on days without a
    /// session are ignored. Returns session id -> matched run.
    public static func match(sessions: [PlannedSession], runs: [CompletedRun]) -> [String: CompletedRun] {
        let runsByDay = Dictionary(grouping: runs, by: \.localDate)
        var used: Set<String> = []
        var matches: [String: CompletedRun] = [:]
        for session in sessions.sorted(by: { $0.date < $1.date }) {
            let minimum = PlanProgressRules.matchShare * session.distanceKm - PlanProgressRules.matchTolerance
            let best = (runsByDay[session.date] ?? [])
                .filter { !used.contains($0.id) && $0.distanceKm >= minimum }
                .max { ($0.distanceKm, $1.id) < ($1.distanceKm, $0.id) }
            if let best {
                used.insert(best.id)
                matches[session.id] = best
            }
        }
        return matches
    }
}
