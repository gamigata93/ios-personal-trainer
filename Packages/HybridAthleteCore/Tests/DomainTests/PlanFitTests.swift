import Foundation
import Testing
import Domain

struct PlanFitTests {
    private func labels(_ results: [PlanFitResult]) -> [FitLabel] {
        results.map(\.label)
    }

    @Test func realDataLabelsAndReadiness() {
        // weekly 17.69, longest 17.0
        let results = PlanFit.evaluate(RunningVolume(weeklyKm: 17.69, longestRunKm: 17.0))

        // 5K: min(17.69/10, 17/4) = 1.769. 10K: min(17.69/15, 17/8) = 1.179.
        // Half: min(17.69/25, 17/13) = 0.708. Marathon: min(17.69/40, 17/21) = 0.442.
        #expect(abs(results[0].readiness - 1.769) < 1e-3)
        #expect(abs(results[1].readiness - 1.179) < 1e-3)
        #expect(abs(results[2].readiness - 0.708) < 1e-3)
        #expect(abs(results[3].readiness - 0.442) < 1e-3)
        #expect(labels(results) == [.greatFit, .bestFit, .stretch, .later])
    }

    @Test func reasonsUseTheRealNumbers() {
        let results = PlanFit.evaluate(RunningVolume(weeklyKm: 17.69, longestRunKm: 17.0))
        #expect(results[0].reason == "Comfortably inside your current base.")
        #expect(results[1].reason == "Matches your recent running: about 18 km a week, longest run 17 km.")
        #expect(results[2].reason == "Needs about 25 km a week and a 13 km long run. You're at 18 and 17.")
        #expect(results[3].reason == "Build a bigger base first. Needs about 40 km a week and a 21 km long run.")
    }

    @Test func readinessExactlyOneIsAFit() {
        // 10K: min(15/15, 8/8) = 1.0 exactly.
        let results = PlanFit.evaluate(RunningVolume(weeklyKm: 15, longestRunKm: 8))
        #expect(results[1].readiness == 1.0)
        #expect(labels(results) == [.greatFit, .bestFit, .later, .later])
    }

    @Test func readinessExactlyPointSevenIsAStretch() {
        // 10K: min(10.5/15, 8/8) = 0.7 exactly.
        let results = PlanFit.evaluate(RunningVolume(weeklyKm: 10.5, longestRunKm: 8))
        #expect(results[1].readiness == 0.7)
        #expect(results[1].label == .stretch)
    }

    @Test func justUnderPointSevenIsLater() {
        let results = PlanFit.evaluate(RunningVolume(weeklyKm: 10.49, longestRunKm: 8))
        #expect(results[1].label == .later)
    }

    @Test func nothingFeasibleStartsWithTheFiveK() {
        // 5K: min(5/10, 3/4) = 0.5.
        let results = PlanFit.evaluate(RunningVolume(weeklyKm: 5, longestRunKm: 3))
        #expect(labels(results) == [.bestFit, .later, .later, .later])
        #expect(results[0].reason == "Start here and build your base.")
    }

    @Test func noRunningAtAllStartsWithTheFiveK() {
        let results = PlanFit.evaluate(.none)
        #expect(labels(results) == [.bestFit, .later, .later, .later])
        #expect(results[0].reason == PlanFit.startHereReason)
    }

    @Test func largestReadyPlanIsBest() {
        // Marathon: min(55/40, 28/21) = 1.333.
        let results = PlanFit.evaluate(RunningVolume(weeklyKm: 55, longestRunKm: 28))
        #expect(labels(results) == [.greatFit, .greatFit, .greatFit, .bestFit])
        #expect(abs(results[3].readiness - 1.3333) < 1e-3)
    }
}
