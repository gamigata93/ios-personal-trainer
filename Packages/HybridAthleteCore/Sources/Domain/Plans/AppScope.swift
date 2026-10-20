import Foundation

/// What the app can plan: races from 5 km up to a full marathon. The ONE place
/// that defines it; widening later means changing these constants. Only plan
/// creation is restricted: existing plans of any distance keep working.
public enum AppScope {
    public static let minRaceKm: Decimal = 5
    /// 42.2 is accepted as the usual rounding of a marathon.
    public static let maxRaceKm = Decimal(string: "42.2") ?? 42
    /// The marathon distance, for labels only.
    public static let marathonKm = Decimal(string: "42.195") ?? 42

    /// Inclusive on both ends, exact decimal comparison.
    public static func isInScope(_ distanceKm: Decimal) -> Bool {
        distanceKm >= minRaceKm && distanceKm <= maxRaceKm
    }

    public static func isInScope(_ distanceKm: Double) -> Bool {
        isInScope(Decimal.exact(distanceKm))
    }
}

/// Which race distances creation accepts: the app's scope, or (DEBUG
/// `-allowAnyDistance`) any positive distance up to 250 km.
public struct RaceDistanceScope: Sendable, Equatable {
    public let isUnrestricted: Bool

    public static let app = RaceDistanceScope(isUnrestricted: false)
    public static let unrestricted = RaceDistanceScope(isUnrestricted: true)
    /// The sanity bounds when unrestricted.
    public static let unrestrictedMaxKm: Decimal = 250

    public init(isUnrestricted: Bool) {
        self.isUnrestricted = isUnrestricted
    }

    public func contains(_ distanceKm: Decimal) -> Bool {
        isUnrestricted ? distanceKm > 0 && distanceKm <= Self.unrestrictedMaxKm : AppScope.isInScope(distanceKm)
    }

    public func contains(_ distanceKm: Double) -> Bool {
        contains(Decimal.exact(distanceKm))
    }
}

extension Decimal {
    /// The decimal a Double prints as ("42.2", not 42.200000000000003).
    public static func exact(_ value: Double) -> Decimal {
        Decimal(string: "\(value)", locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(value)
    }
}

/// Reads a typed race distance. Both "." and "," work as the decimal separator
/// whatever the locale (a phone may use either); surrounding spaces are ignored.
/// Empty text, letters, inner spaces, two separators and thousands grouping
/// give nil. Nothing is rounded.
public enum RaceDistanceParser {
    public static func parse(_ text: String, locale: Locale) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let separators = trimmed.filter { $0 == "." || $0 == "," }
        guard separators.count <= 1, trimmed.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }) else { return nil }
        let parts = trimmed.split(separator: separators.first ?? " ", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return Decimal(string: trimmed.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// The four standard distances offered as chips on Race setup.
public enum DistanceShortcut: String, Sendable, Equatable, CaseIterable {
    case fiveK = "5K", tenK = "10K", half = "Half", marathon = "Marathon"

    /// What a tap fills in: 5, 10, 21.1, 42.2.
    public var value: Decimal {
        switch self {
        case .fiveK: 5
        case .tenK: 10
        case .half: Decimal(string: "21.1") ?? 21
        case .marathon: Decimal(string: "42.2") ?? 42
        }
    }

    /// "half marathon".
    public var spokenName: String {
        switch self {
        case .fiveK: "5K"
        case .tenK: "10K"
        case .half: "half marathon"
        case .marathon: "marathon"
        }
    }

    /// "Set distance to 21.1 kilometres, half marathon".
    public var accessibilityLabel: String {
        "Set distance to \(DistanceText.km(value)) kilometres, \(spokenName)"
    }

    /// The chip within 0.05 km of `distanceKm`, if any (21.0975 is Half, 42.195 Marathon).
    public static func selected(for distanceKm: Decimal?) -> DistanceShortcut? {
        guard let distanceKm else { return nil }
        let tolerance = Decimal(string: "0.05") ?? 0
        return allCases.first { abs($0.value - distanceKm) <= tolerance }
    }

    /// The chip for a suggested plan.
    public static func shortcut(for plan: PlanKind) -> DistanceShortcut {
        switch plan {
        case .fiveK: .fiveK
        case .tenK: .tenK
        case .halfMarathon: .half
        case .marathon: .marathon
        }
    }
}

/// Distance text for prompts and labels: whole numbers without decimals ("15"),
/// otherwise up to 3 decimals with trailing zeros trimmed ("21.1", "42.195").
public enum DistanceText {
    public static func km(_ value: Decimal) -> String {
        var source = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 3, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    public static func km(_ value: Double) -> String {
        km(Decimal.exact(value))
    }
}
