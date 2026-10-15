import Foundation

public enum BiologicalSex: String, Sendable, Equatable, Codable {
    case female
    case male
    case other
    case notSet
}

/// The characteristics a health source exposes. Age only: the date of birth
/// itself never leaves the adapter.
public struct HealthProfile: Sendable, Equatable {
    public let ageYears: Int?
    public let biologicalSex: BiologicalSex?

    public init(ageYears: Int?, biologicalSex: BiologicalSex?) {
        self.ageYears = ageYears
        self.biologicalSex = biologicalSex
    }

    /// Nothing usable came back, which looks the same as no access.
    public var isEmpty: Bool {
        ageYears == nil && (biologicalSex == nil || biologicalSex == .notSet)
    }
}

public struct ProfileSection: Sendable, Equatable {
    public let status: ReadStatus
    public let ageYears: Int?
    public let biologicalSex: BiologicalSex?

    public init(status: ReadStatus, ageYears: Int?, biologicalSex: BiologicalSex?) {
        self.status = status
        self.ageYears = ageYears
        self.biologicalSex = biologicalSex
    }

    public static func unread(_ status: ReadStatus) -> ProfileSection {
        ProfileSection(status: status, ageYears: nil, biologicalSex: nil)
    }
}
