import Foundation

public protocol ConfigurationProvider: Sendable {
    var identifier: String { get }
    var displayName: String { get }
    var capabilities: ProviderCapabilities { get }

    func detect(context: DetectionContext) async throws -> DetectionResult
    func snapshot(context: SnapshotContext) async throws -> SnapshotSection
    func validate(section: SnapshotSection, context: ValidationContext) async throws -> ValidationResult
    func planApply(section: SnapshotSection, context: ApplyContext) async throws -> [PlannedAction]
    func apply(action: PlannedAction, context: ApplyContext) async throws -> ApplyResult
}

public struct ProviderCapabilities: Codable, Equatable, Sendable {
    public var canDetect: Bool
    public var canSnapshot: Bool
    public var canValidate: Bool
    public var canPlanApply: Bool
    public var canApply: Bool

    public init(
        canDetect: Bool = true,
        canSnapshot: Bool = true,
        canValidate: Bool = true,
        canPlanApply: Bool = true,
        canApply: Bool = false
    ) {
        self.canDetect = canDetect
        self.canSnapshot = canSnapshot
        self.canValidate = canValidate
        self.canPlanApply = canPlanApply
        self.canApply = canApply
    }
}

public struct DetectionContext: Sendable {
    public var commandRunner: CommandRunner

    public init(commandRunner: CommandRunner) {
        self.commandRunner = commandRunner
    }
}

public struct SnapshotContext: Sendable {
    public var commandRunner: CommandRunner

    public init(commandRunner: CommandRunner) {
        self.commandRunner = commandRunner
    }
}

public struct ValidationContext: Sendable {
    public init() {
        // Reserved for future validation options; currently stateless.
    }
}

public struct ApplyContext: Sendable {
    public var commandRunner: CommandRunner
    public var dryRun: Bool

    public init(commandRunner: CommandRunner, dryRun: Bool = true) {
        self.commandRunner = commandRunner
        self.dryRun = dryRun
    }
}

public struct DetectionResult: Codable, Equatable, Sendable {
    public var providerIdentifier: String
    public var status: OperationStatus
    public var message: String

    public init(providerIdentifier: String, status: OperationStatus, message: String) {
        self.providerIdentifier = providerIdentifier
        self.status = status
        self.message = message
    }
}

public struct ValidationResult: Codable, Equatable, Sendable {
    public var status: OperationStatus
    public var messages: [String]

    public init(status: OperationStatus, messages: [String] = []) {
        self.status = status
        self.messages = messages
    }
}

public struct PlannedAction: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var providerIdentifier: String
    public var kind: PlannedActionKind
    public var summary: String
    public var requiresElevation: Bool

    public init(
        id: UUID = UUID(),
        providerIdentifier: String,
        kind: PlannedActionKind,
        summary: String,
        requiresElevation: Bool = false
    ) {
        self.id = id
        self.providerIdentifier = providerIdentifier
        self.kind = kind
        self.summary = summary
        self.requiresElevation = requiresElevation
    }
}

public enum PlannedActionKind: String, Codable, Equatable, Sendable {
    case install
    case configure
    case skip
    case blocked
    case requiresUserAction
}

public struct ApplyResult: Codable, Equatable, Sendable {
    public var actionID: UUID
    public var status: OperationStatus
    public var message: String

    public init(actionID: UUID, status: OperationStatus, message: String) {
        self.actionID = actionID
        self.status = status
        self.message = message
    }
}

public enum OperationStatus: String, Codable, Equatable, Sendable {
    case fatal
    case blocked
    case warning
    case skipped
    case unsupported
    case success
    case info
}
