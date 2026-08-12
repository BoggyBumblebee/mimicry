import Foundation

public struct EnvironmentSnapshotProvider: ConfigurationProvider {
    public let identifier = "environment"
    public let displayName = "Environment"
    public let capabilities = ProviderCapabilities(canPlanApply: false, canApply: false)

    public init() {
        // Stateless provider; public initializer exposes it outside MimicryCore.
    }

    public func detect(context _: DetectionContext) async throws -> DetectionResult {
        DetectionResult(
            providerIdentifier: identifier,
            status: .success,
            message: "Environment metadata can be captured from detected Mac capabilities."
        )
    }

    public func snapshot(context: SnapshotContext) async throws -> SnapshotSection {
        guard let capabilities = context.capabilities else {
            return SnapshotSection(
                identifier: identifier,
                displayName: displayName,
                items: [],
                warnings: [
                    SnapshotWarning(
                        code: "environment.capabilities-missing",
                        message: "Mac capabilities were not supplied; environment snapshot was skipped."
                    )
                ]
            )
        }

        return SnapshotSection(
            identifier: identifier,
            displayName: displayName,
            items: [
                SnapshotItem(key: "macos.version", value: .string(capabilities.macOSVersion)),
                SnapshotItem(key: "architecture", value: .string(capabilities.architecture.rawValue)),
                SnapshotItem(key: "hardware.model", value: .string(capabilities.hardwareModel), classification: .hardwareSpecific),
                SnapshotItem(key: "hostname", value: .string(capabilities.hostname), classification: .machineSpecific),
                SnapshotItem(key: "username", value: .string(capabilities.username), classification: .userMustReview, applicability: .userSpecific),
                SnapshotItem(key: "admin", value: .bool(capabilities.hasAdministratorPrivileges)),
                SnapshotItem(key: "command-line-tools", value: .bool(capabilities.hasCommandLineTools)),
                SnapshotItem(key: "xcode.version", value: capabilities.xcodeVersion.map(SnapshotValue.string) ?? .absent),
                SnapshotItem(key: "filevault", value: .string(capabilities.fileVaultState.rawValue)),
                SnapshotItem(key: "sip", value: .string(capabilities.sipState.rawValue)),
                SnapshotItem(key: "icloud", value: .string(capabilities.iCloudState.rawValue)),
                SnapshotItem(key: "app-store", value: .string(capabilities.appStoreState.rawValue)),
                SnapshotItem(key: "management", value: .string(capabilities.managementState.rawValue), classification: managementClassification(capabilities.managementState))
            ]
        )
    }

    public func validate(section: SnapshotSection, context _: ValidationContext) async throws -> ValidationResult {
        section.identifier == identifier
            ? ValidationResult(status: .success)
            : ValidationResult(status: .warning, messages: ["Expected environment section."])
    }

    public func planApply(section _: SnapshotSection, context _: ApplyContext) async throws -> [PlannedAction] {
        [
            PlannedAction(
                providerIdentifier: identifier,
                kind: .skip,
                summary: "Environment metadata is informational and is not applied."
            )
        ]
    }

    public func apply(action: PlannedAction, context _: ApplyContext) async throws -> ApplyResult {
        ApplyResult(actionID: action.id, status: .skipped, message: "Environment metadata is informational.")
    }

    private func managementClassification(_ state: CapabilityState) -> ConfigurationClassification {
        state == .managed ? .managed : .safeConfiguration
    }
}
