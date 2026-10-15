import Foundation
import Domain

/// One metric of the Recovery section, finished.
public enum RecoveryUpdate: Sendable, Equatable {
    case sleep(SleepRefreshResult)
    case hrv(HRVRefreshResult)
    case restingHr(RestingHRRefreshResult)
}

/// Refreshes sleep, HRV and resting heart rate, publishing each as it finishes.
/// Sleep and resting heart rate start together; HRV starts when sleep finishes,
/// because its windows come from the sleep nights. A failing metric never
/// blocks the others.
public struct RefreshRecoverySection: Sendable {
    private let refreshSleep: RefreshSleep
    private let loadCachedSleep: LoadCachedSleep
    private let refreshRecovery: RefreshRecovery

    public init(refreshSleep: RefreshSleep, loadCachedSleep: LoadCachedSleep, refreshRecovery: RefreshRecovery) {
        self.refreshSleep = refreshSleep
        self.loadCachedSleep = loadCachedSleep
        self.refreshRecovery = refreshRecovery
    }

    public func execute() -> AsyncStream<RecoveryUpdate> {
        let refreshSleep = refreshSleep
        let loadCachedSleep = loadCachedSleep
        let refreshRecovery = refreshRecovery
        return AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        continuation.yield(.restingHr(await refreshRecovery.refreshRestingHR()))
                    }
                    group.addTask {
                        let sleep = await refreshSleep.execute()
                        continuation.yield(.sleep(sleep))
                        let nights = await Self.nightsForHRV(sleep.state, cached: loadCachedSleep)
                        continuation.yield(.hrv(await refreshRecovery.refreshHRV(sleepNights: nights)))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Fresh nights when sleep was read; the cached nights when sleep was locked
    /// or failed; none otherwise (HRV then uses the fallback windows only).
    static func nightsForHRV(_ state: SectionState<[SleepNight]>, cached: LoadCachedSleep) async -> [SleepNight] {
        switch state {
        case .ready(let nights, _, _): return nights
        case .locked(let nights, _): return nights ?? []
        case .failed: return await cached.execute().value ?? []
        case .loading, .emptyOrNotAllowed: return []
        }
    }
}
