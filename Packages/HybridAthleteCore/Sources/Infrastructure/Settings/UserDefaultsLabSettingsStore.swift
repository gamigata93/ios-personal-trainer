import Foundation
import Application
import Domain

/// The Lab's consent flag, caps, cost scenario and coach model in UserDefaults. The API key
/// never goes here (it is in the Keychain behind `SecretStore`).
public struct UserDefaultsLabSettingsStore: LabSettingsStore, @unchecked Sendable {
    private enum Key {
        static let consent = "lab.anthropicConsent"
        static let perRunCap = "lab.perRunCapMicros"
        static let monthlyCap = "lab.monthlyCapMicros"
        static let plansPerMonth = "lab.plansPerMonth"
        static let notesPerMonth = "lab.notesPerMonth"
        static let coachModel = "lab.coachModelPreference"
    }

    // UserDefaults is thread-safe.
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() async -> LabSettings {
        func int64(_ key: String, default value: Int64) -> Int64 {
            (defaults.object(forKey: key) as? NSNumber).map { $0.int64Value }.flatMap { $0 > 0 ? $0 : nil } ?? value
        }
        func int(_ key: String, default value: Int) -> Int {
            (defaults.object(forKey: key) as? NSNumber)?.intValue ?? value
        }
        return LabSettings(
            consentGiven: defaults.bool(forKey: Key.consent),
            caps: SpendCaps(
                perRunMicros: int64(Key.perRunCap, default: SpendCaps.defaults.perRunMicros),
                monthlyMicros: int64(Key.monthlyCap, default: SpendCaps.defaults.monthlyMicros)
            ),
            scenario: CostScenario(
                plansPerMonth: int(Key.plansPerMonth, default: CostScenario.defaults.plansPerMonth),
                notesPerMonth: int(Key.notesPerMonth, default: CostScenario.defaults.notesPerMonth)
            ),
            coachModelPreference: defaults.string(forKey: Key.coachModel).flatMap(CoachModelPreference.init(id:)) ?? .automatic
        )
    }

    public func save(_ settings: LabSettings) async {
        defaults.set(settings.consentGiven, forKey: Key.consent)
        defaults.set(NSNumber(value: settings.caps.perRunMicros), forKey: Key.perRunCap)
        defaults.set(NSNumber(value: settings.caps.monthlyMicros), forKey: Key.monthlyCap)
        defaults.set(settings.scenario.plansPerMonth, forKey: Key.plansPerMonth)
        defaults.set(settings.scenario.notesPerMonth, forKey: Key.notesPerMonth)
        defaults.set(settings.coachModelPreference.id, forKey: Key.coachModel)
    }
}
