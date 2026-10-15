import Foundation
import FoundationModels
import Application
import Domain

/// What the device says about each model: availability, the context size (read
/// at runtime, never hardcoded) and Private Cloud Compute's daily quota. A Claude
/// model is available when a key is saved; the package exposes no context size.
public struct FoundationModelAvailabilityChecker: ModelAvailabilityChecker {
    private let configuration: FoundationModelsConfiguration
    private let secrets: (any SecretStore)?

    public init(configuration: FoundationModelsConfiguration = .current, secrets: (any SecretStore)? = nil) {
        self.configuration = configuration
        self.secrets = secrets
    }

    public func status(for model: ModelChoice) async -> ModelStatus {
        switch model {
        case .onDevice:
            let system = SystemLanguageModel.default
            let availability = FoundationModelsMapping.availability(system.availability)
            return ModelStatus(availability: availability, contextSize: availability.isAvailable ? system.contextSize : nil)
        case .privateCloud:
            // Touching the model without the managed entitlement is not supported.
            guard configuration.privateCloudComputeEnabled else { return ModelStatus(availability: .notEnabledForBuild) }
            let cloud = PrivateCloudComputeLanguageModel()
            let availability = FoundationModelsMapping.availability(cloud.availability)
            guard availability.isAvailable else { return ModelStatus(availability: availability) }
            let contextSize = try? await cloud.contextSize
            return ModelStatus(availability: availability, contextSize: contextSize, quota: FoundationModelsMapping.quota(cloud.quotaUsage))
        case .anthropic:
            let hasKey = await secrets?.hasSecret(.anthropicAPIKey) ?? false
            return ModelStatus(availability: hasKey ? .available : .needsAPIKey)
        }
    }
}
