import Foundation

public struct ICloudSnapshotProvider: ConfigurationProvider {
    public typealias FileExists = @Sendable (URL) -> Bool

    public let identifier = "icloud"
    public let displayName = "iCloud"
    public let capabilities = ProviderCapabilities(canApply: false)

    private let homeDirectory: URL
    private let applicationPaths: MacCapabilityApplicationPaths
    private let fileExists: FileExists

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationPaths: MacCapabilityApplicationPaths = .macOSDefault,
        fileExists: @escaping FileExists = { FileManager.default.fileExists(atPath: $0.path) }
    ) {
        self.homeDirectory = homeDirectory
        self.applicationPaths = applicationPaths
        self.fileExists = fileExists
    }

    public func detect(context _: DetectionContext) async throws -> DetectionResult {
        let state = localState()
        return DetectionResult(
            providerIdentifier: identifier,
            status: state == .available ? .success : .warning,
            message: state == .available
                ? "iCloud Drive local metadata is available."
                : "iCloud Drive local metadata requires user review."
        )
    }

    public func snapshot(context: SnapshotContext) async throws -> SnapshotSection {
        let containerExists = iCloudContainerExists()
        let state = context.capabilities?.iCloudState ?? state(forContainerExists: containerExists)
        var warnings: [SnapshotWarning] = []

        if state != .available {
            warnings.append(
                SnapshotWarning(
                    code: "icloud.requires-user-action",
                    message: "iCloud Drive local metadata could not be confirmed; sign-in and sync state require user review."
                )
            )
        }

        return SnapshotSection(
            identifier: identifier,
            displayName: displayName,
            items: [
                SnapshotItem(
                    key: "icloud.state",
                    value: .string(state.rawValue),
                    classification: classification(for: state),
                    applicability: .userSpecific
                ),
                SnapshotItem(
                    key: "icloud.drive-container",
                    value: .object([
                        "path": displayPath,
                        "exists": String(containerExists),
                        "status": state.rawValue
                    ]),
                    classification: classification(for: state),
                    applicability: .userSpecific
                ),
                SnapshotItem(
                    key: "icloud.auth-state",
                    value: .string("excluded"),
                    classification: .excluded,
                    applicability: .userSpecific
                )
            ],
            warnings: warnings
        )
    }

    public func validate(section: SnapshotSection, context _: ValidationContext) async throws -> ValidationResult {
        section.identifier == identifier
            ? ValidationResult(status: .success)
            : ValidationResult(status: .warning, messages: ["Expected iCloud section."])
    }

    public func planApply(section _: SnapshotSection, context _: ApplyContext) async throws -> [PlannedAction] {
        [
            PlannedAction(
                providerIdentifier: identifier,
                kind: .requiresUserAction,
                summary: "iCloud sign-in and sync state cannot be applied automatically; user action is required."
            )
        ]
    }

    public func apply(action: PlannedAction, context _: ApplyContext) async throws -> ApplyResult {
        ApplyResult(actionID: action.id, status: .skipped, message: "iCloud apply is not implemented because authentication requires user action.")
    }

    private var displayPath: String {
        (["~"] + applicationPaths.iCloudDocumentsPathComponents).joined(separator: String(UnicodeScalar(47)))
    }

    private func localState() -> CapabilityState {
        state(forContainerExists: iCloudContainerExists())
    }

    private func iCloudContainerExists() -> Bool {
        fileExists(applicationPaths.iCloudDocumentsURL(relativeTo: homeDirectory))
    }

    private func state(forContainerExists exists: Bool) -> CapabilityState {
        exists ? .available : .requiresUserAction
    }

    private func classification(for state: CapabilityState) -> ConfigurationClassification {
        state == .available ? .safeConfiguration : .userMustReview
    }
}
