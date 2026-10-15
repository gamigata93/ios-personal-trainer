import Foundation

/// Where a value falls relative to the published range.
public enum PercentileEdge: Sendable, Equatable {
    /// Inside the anchors (or exactly on one).
    case none
    /// Strictly better than the best anchor.
    case top
    /// Strictly worse than the worst anchor.
    case bottom
}

public enum FitnessBand: String, Sendable, Equatable, CaseIterable {
    case low
    case belowAverage
    case average
    case aboveAverage
    case excellent
}

public struct PercentileResult: Sendable, Equatable {
    /// Share of the reference population this value beats, 0 to 100.
    /// At an edge it is the nearest anchor's value.
    public let betterThanPercent: Double
    public let edge: PercentileEdge

    public init(betterThanPercent: Double, edge: PercentileEdge) {
        self.betterThanPercent = betterThanPercent
        self.edge = edge
    }

    /// Below 20 Low, below 40 Below average, below 60 Average, below 80 Above
    /// average, otherwise Excellent. Edges are always the extreme band.
    public var band: FitnessBand {
        switch edge {
        case .top: return .excellent
        case .bottom: return .low
        case .none: break
        }
        switch betterThanPercent {
        case ..<20: return .low
        case ..<40: return .belowAverage
        case ..<60: return .average
        case ..<80: return .aboveAverage
        default: return .excellent
        }
    }
}

/// Piecewise-linear percentile through a table's anchors.
public enum PercentileCalculator {
    /// For VO2 max the result is the percentile; for resting heart rate, where
    /// lower is better, it is 100 minus the percentile.
    public static func result(for value: Double, in table: NormTable) -> PercentileResult? {
        guard let first = table.anchors.first, let last = table.anchors.last else { return nil }
        let higherIsBetter = table.metric.higherIsBetter

        func betterThan(_ percentile: Double) -> Double {
            higherIsBetter ? percentile : 100 - percentile
        }

        if value < first.v {
            return PercentileResult(betterThanPercent: betterThan(first.p), edge: higherIsBetter ? .bottom : .top)
        }
        if value > last.v {
            return PercentileResult(betterThanPercent: betterThan(last.p), edge: higherIsBetter ? .top : .bottom)
        }
        return PercentileResult(betterThanPercent: betterThan(percentile(of: value, anchors: table.anchors)), edge: .none)
    }

    /// The value is known to lie within the anchors' range.
    private static func percentile(of value: Double, anchors: [NormAnchor]) -> Double {
        if let exact = anchors.first(where: { $0.v == value }) {
            return exact.p
        }
        for (lower, upper) in zip(anchors, anchors.dropFirst()) where value > lower.v && value < upper.v {
            return lower.p + (upper.p - lower.p) * (value - lower.v) / (upper.v - lower.v)
        }
        return anchors.last?.p ?? 0
    }
}
