import Foundation
import Observation
import Domain
import Application

/// Asks for Apple Health access once, then moves on whatever the answer:
/// HealthKit never says what was granted.
@MainActor
@Observable
final class ConnectHealthViewModel {
    private(set) var isRequesting = false

    /// DEBUG persona choices; empty in release.
    let personaChoices: [String]

    private let requestHealthAccess: RequestHealthAccess
    private let onFinished: @MainActor () -> Void
    private let onChoosePersona: @MainActor (String?) -> Void

    init(
        requestHealthAccess: RequestHealthAccess,
        onFinished: @escaping @MainActor () -> Void,
        personaChoices: [String] = [],
        onChoosePersona: @escaping @MainActor (String?) -> Void = { _ in }
    ) {
        self.requestHealthAccess = requestHealthAccess
        self.onFinished = onFinished
        self.personaChoices = personaChoices
        self.onChoosePersona = onChoosePersona
    }

    func allow() async {
        guard !isRequesting else { return }
        isRequesting = true
        // The outcome does not change where the app goes next.
        try? await requestHealthAccess.execute()
        onFinished()
    }

    /// DEBUG only: read a made-up persona instead of Apple Health (`nil` = real data).
    func choosePersona(_ id: String?) {
        onChoosePersona(id)
    }
}
