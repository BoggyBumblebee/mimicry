import Foundation

public struct FinderSnapshotProvider: ConfigurationProvider {
    public let identifier = "finder"
    public let displayName = "Finder"
    public let capabilities = ProviderCapabilities(canApply: false)

    private let paths: SnapshotProviderToolPaths
    private let preferences: [FinderPreferenceSpec]

    public init(
        paths: SnapshotProviderToolPaths = .macOSDefault,
        preferences: [FinderPreferenceSpec] = FinderPreferenceSpec.defaultPreferences
    ) {
        self.paths = paths
        self.preferences = preferences
    }

    public func detect(context: DetectionContext) async throws -> DetectionResult {
        let result = try await context.commandRunner.run(
            executable: paths.defaults,
            arguments: ["read", FinderPreferenceDomain.finder.rawValue],
            environment: nil
        )

        return DetectionResult(
            providerIdentifier: identifier,
            status: result.exitCode == 0 ? .success : .warning,
            message: result.exitCode == 0 ? "Finder preferences are readable." : "Finder preferences could not be read."
        )
    }

    public func snapshot(context: SnapshotContext) async throws -> SnapshotSection {
        var items: [SnapshotItem] = []
        var warnings: [SnapshotWarning] = []

        for preference in preferences {
            let result = await read(preference: preference, context: context)
            if result.exitCode == 0 {
                items.append(preference.snapshotItem(rawValue: result.standardOutput))
            } else {
                items.append(preference.absentSnapshotItem())
                if shouldWarn(for: result) {
                    warnings.append(
                        SnapshotWarning(
                            code: "finder.preference-unreadable.\(preference.key)",
                            message: "Finder preference `\(preference.key)` could not be read."
                        )
                    )
                }
            }
        }

        return SnapshotSection(
            identifier: identifier,
            displayName: displayName,
            items: items,
            warnings: warnings
        )
    }

    public func validate(section: SnapshotSection, context _: ValidationContext) async throws -> ValidationResult {
        section.identifier == identifier
            ? ValidationResult(status: .success)
            : ValidationResult(status: .warning, messages: ["Expected Finder section."])
    }

    public func planApply(section _: SnapshotSection, context _: ApplyContext) async throws -> [PlannedAction] {
        [
            PlannedAction(
                providerIdentifier: identifier,
                kind: .requiresUserAction,
                summary: "Finder apply planning starts in Phase 5 after preference backups are implemented."
            )
        ]
    }

    public func apply(action: PlannedAction, context _: ApplyContext) async throws -> ApplyResult {
        ApplyResult(actionID: action.id, status: .skipped, message: "Finder apply is not implemented yet.")
    }

    private func read(preference: FinderPreferenceSpec, context: SnapshotContext) async -> CommandResult {
        do {
            return try await context.commandRunner.run(
                executable: paths.defaults,
                arguments: ["read", preference.domain.rawValue, preference.key],
                environment: nil
            )
        } catch {
            return CommandResult(
                executable: paths.defaults.path,
                arguments: ["read", preference.domain.rawValue, preference.key],
                exitCode: 1,
                standardError: String(describing: error)
            )
        }
    }

    private func shouldWarn(for result: CommandResult) -> Bool {
        let output = [result.standardOutput, result.standardError].joined(separator: "\n").lowercased()
        return !output.contains("does not exist")
    }
}

public struct FinderPreferenceSpec: Equatable, Sendable {
    public var domain: FinderPreferenceDomain
    public var key: String
    public var valueKind: FinderPreferenceValueKind
    public var classification: ConfigurationClassification
    public var applicability: ConfigurationApplicability

    public init(
        domain: FinderPreferenceDomain = .finder,
        key: String,
        valueKind: FinderPreferenceValueKind,
        classification: ConfigurationClassification = .safeConfiguration,
        applicability: ConfigurationApplicability = .universal
    ) {
        self.domain = domain
        self.key = key
        self.valueKind = valueKind
        self.classification = classification
        self.applicability = applicability
    }

    public static let defaultPreferences = [
        FinderPreferenceSpec(key: "AppleShowAllFiles", valueKind: .bool),
        FinderPreferenceSpec(key: "ShowPathbar", valueKind: .bool),
        FinderPreferenceSpec(key: "ShowStatusBar", valueKind: .bool),
        FinderPreferenceSpec(key: "FXPreferredViewStyle", valueKind: .string),
        FinderPreferenceSpec(key: "FXDefaultSearchScope", valueKind: .string),
        FinderPreferenceSpec(key: "NewWindowTarget", valueKind: .string),
        FinderPreferenceSpec(
            key: "NewWindowTargetPath",
            valueKind: .string,
            classification: .userMustReview,
            applicability: .userSpecific
        ),
        FinderPreferenceSpec(key: "WarnOnEmptyTrash", valueKind: .bool),
        FinderPreferenceSpec(key: "ShowExternalHardDrivesOnDesktop", valueKind: .bool),
        FinderPreferenceSpec(key: "ShowHardDrivesOnDesktop", valueKind: .bool),
        FinderPreferenceSpec(key: "ShowMountedServersOnDesktop", valueKind: .bool),
        FinderPreferenceSpec(key: "ShowRemovableMediaOnDesktop", valueKind: .bool)
    ]

    func snapshotItem(rawValue: String) -> SnapshotItem {
        SnapshotItem(
            key: "finder.\(key)",
            value: valueKind.snapshotValue(from: rawValue),
            classification: classification,
            applicability: applicability
        )
    }

    func absentSnapshotItem() -> SnapshotItem {
        SnapshotItem(
            key: "finder.\(key)",
            value: .absent,
            classification: classification,
            applicability: applicability
        )
    }
}

public enum FinderPreferenceDomain: String, Equatable, Sendable {
    case finder = "com.apple.finder"
}

public enum FinderPreferenceValueKind: Equatable, Sendable {
    case bool
    case string

    func snapshotValue(from rawValue: String) -> SnapshotValue {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        switch self {
        case .bool:
            return parseBool(value).map(SnapshotValue.bool) ?? .absent
        case .string:
            return value.trimmedNilIfEmpty.map(SnapshotValue.string) ?? .absent
        }
    }

    private func parseBool(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "1", "true", "yes":
            true
        case "0", "false", "no":
            false
        default:
            nil
        }
    }
}
