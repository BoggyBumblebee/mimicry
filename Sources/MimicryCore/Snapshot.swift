import Foundation

public struct MimicrySnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var mimicryVersion: String
    public var createdAt: Date
    public var source: SnapshotSource
    public var sections: [SnapshotSection]

    public init(
        schemaVersion: Int = 1,
        mimicryVersion: String,
        createdAt: Date = Date(),
        source: SnapshotSource,
        sections: [SnapshotSection] = []
    ) {
        self.schemaVersion = schemaVersion
        self.mimicryVersion = mimicryVersion
        self.createdAt = createdAt
        self.source = source
        self.sections = sections
    }
}

public struct SnapshotSource: Codable, Equatable, Sendable {
    public var macOSVersion: String
    public var architecture: String
    public var hardwareModel: String
    public var hostname: String
    public var username: String

    public init(
        macOSVersion: String,
        architecture: String,
        hardwareModel: String,
        hostname: String,
        username: String
    ) {
        self.macOSVersion = macOSVersion
        self.architecture = architecture
        self.hardwareModel = hardwareModel
        self.hostname = hostname
        self.username = username
    }
}

public struct SnapshotSection: Codable, Equatable, Sendable, Identifiable {
    public var id: String { identifier }

    public var identifier: String
    public var displayName: String
    public var providerVersion: String
    public var capturedAt: Date
    public var items: [SnapshotItem]
    public var warnings: [SnapshotWarning]

    public init(
        identifier: String,
        displayName: String,
        providerVersion: String = "1",
        capturedAt: Date = Date(),
        items: [SnapshotItem] = [],
        warnings: [SnapshotWarning] = []
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.providerVersion = providerVersion
        self.capturedAt = capturedAt
        self.items = items
        self.warnings = warnings
    }
}

public struct SnapshotItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String { key }

    public var key: String
    public var value: SnapshotValue
    public var classification: ConfigurationClassification
    public var applicability: ConfigurationApplicability

    public init(
        key: String,
        value: SnapshotValue,
        classification: ConfigurationClassification = .safeConfiguration,
        applicability: ConfigurationApplicability = .universal
    ) {
        self.key = key
        self.value = value
        self.classification = classification
        self.applicability = applicability
    }
}

public enum SnapshotValue: Codable, Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case stringArray([String])
    case object([String: String])
    case absent
}

public enum ConfigurationClassification: String, Codable, Equatable, Sendable {
    case safeConfiguration
    case potentiallySensitive
    case excluded
    case userMustReview
    case machineSpecific
    case hardwareSpecific
    case managed
    case unsupported
}

public enum ConfigurationApplicability: String, Codable, Equatable, Sendable {
    case universal
    case appleSiliconOnly
    case intelOnly
    case laptopOnly
    case desktopOnly
    case externalDisplayDependent
    case externalInputDeviceDependent
    case userSpecific
    case machineSpecific
    case managedDeviceOnly
}

public struct SnapshotWarning: Codable, Equatable, Sendable, Identifiable {
    public var id: String { code }

    public var code: String
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}
