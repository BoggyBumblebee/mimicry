import Foundation

public struct TerminalSnapshotProvider: ConfigurationProvider {
    public let identifier = "terminal"
    public let displayName = "Terminal"
    public let capabilities = ProviderCapabilities(canApply: false)

    private let homeDirectory: URL
    private let environment: [String: String]
    private let configFiles: [TerminalConfigurationFileSpec]
    private let scanner: SecretScanner

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String]? = nil,
        configFiles: [TerminalConfigurationFileSpec] = TerminalConfigurationFileSpec.defaultFiles,
        scanner: SecretScanner = SecretScanner()
    ) {
        self.homeDirectory = homeDirectory
        self.environment = TerminalSnapshotProvider.selectedEnvironment(
            from: environment ?? ProcessInfo.processInfo.environment
        )
        self.configFiles = configFiles
        self.scanner = scanner
    }

    public func detect(context _: DetectionContext) async throws -> DetectionResult {
        DetectionResult(
            providerIdentifier: identifier,
            status: .success,
            message: "Terminal shell metadata and reviewed shell configuration files can be inspected."
        )
    }

    public func snapshot(context _: SnapshotContext) async throws -> SnapshotSection {
        var items = shellItems()
        var warnings: [SnapshotWarning] = []

        for configFile in configFiles {
            let result = scan(configFile: configFile)
            items.append(result.item)
            warnings.append(contentsOf: result.warnings)
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
            : ValidationResult(status: .warning, messages: ["Expected Terminal section."])
    }

    public func planApply(section _: SnapshotSection, context _: ApplyContext) async throws -> [PlannedAction] {
        [
            PlannedAction(
                providerIdentifier: identifier,
                kind: .requiresUserAction,
                summary: "Terminal apply planning starts after backups and secret-safe file reconciliation are implemented."
            )
        ]
    }

    public func apply(action: PlannedAction, context _: ApplyContext) async throws -> ApplyResult {
        ApplyResult(actionID: action.id, status: .skipped, message: "Terminal apply is not implemented yet.")
    }

    private static func selectedEnvironment(from environment: [String: String]) -> [String: String] {
        ["SHELL", "TERM", "TERM_PROGRAM"].reduce(into: [:]) { selected, key in
            selected[key] = environment[key]
        }
    }

    private func shellItems() -> [SnapshotItem] {
        let shellPath = (environment["SHELL"] ?? "").trimmedNilIfEmpty
        let shellName = shellPath.map { URL(fileURLWithPath: $0).lastPathComponent }

        return [
            SnapshotItem(
                key: "terminal.shell.path",
                value: shellPath.map(SnapshotValue.string) ?? .absent,
                classification: .userMustReview,
                applicability: .userSpecific
            ),
            SnapshotItem(
                key: "terminal.shell.name",
                value: shellName.map(SnapshotValue.string) ?? .absent,
                classification: .safeConfiguration,
                applicability: .userSpecific
            ),
            SnapshotItem(
                key: "terminal.term",
                value: (environment["TERM"] ?? "").trimmedNilIfEmpty.map(SnapshotValue.string) ?? .absent,
                classification: .safeConfiguration,
                applicability: .userSpecific
            ),
            SnapshotItem(
                key: "terminal.term-program",
                value: (environment["TERM_PROGRAM"] ?? "").trimmedNilIfEmpty.map(SnapshotValue.string) ?? .absent,
                classification: .safeConfiguration,
                applicability: .userSpecific
            )
        ]
    }

    private func scan(configFile: TerminalConfigurationFileSpec) -> TerminalConfigurationScanResult {
        let fileURL = homeDirectory.appendingPathComponent(configFile.relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return TerminalConfigurationScanResult(
                item: configFile.snapshotItem(
                    status: .absent,
                    lineCount: 0,
                    findingCount: 0,
                    ruleIDs: []
                ),
                warnings: []
            )
        }

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let scanResult = scanner.scan(content)
            let status: TerminalConfigurationStatus = scanResult.isClean ? .metadataCaptured : .redacted
            let item = configFile.snapshotItem(
                status: status,
                lineCount: lineCount(in: content),
                findingCount: scanResult.findings.count,
                ruleIDs: scanResult.ruleIDs
            )

            guard !scanResult.isClean else {
                return TerminalConfigurationScanResult(item: item, warnings: [])
            }

            return TerminalConfigurationScanResult(
                item: item,
                warnings: [
                    SnapshotWarning(
                        code: "terminal.config-redacted.\(configFile.keyComponent)",
                        message: "Terminal configuration `\(configFile.relativePath)` contains secret-like values; file contents were not captured."
                    )
                ]
            )
        } catch {
            return TerminalConfigurationScanResult(
                item: configFile.snapshotItem(
                    status: .unreadable,
                    lineCount: 0,
                    findingCount: 0,
                    ruleIDs: []
                ),
                warnings: [
                    SnapshotWarning(
                        code: "terminal.config-unreadable.\(configFile.keyComponent)",
                        message: "Terminal configuration `\(configFile.relativePath)` could not be read."
                    )
                ]
            )
        }
    }

    private func lineCount(in content: String) -> Int {
        content.isEmpty ? 0 : content.split(separator: "\n", omittingEmptySubsequences: false).count
    }
}

public struct TerminalConfigurationFileSpec: Equatable, Sendable {
    public var relativePath: String
    public var displayName: String

    public init(relativePath: String, displayName: String) {
        self.relativePath = relativePath
        self.displayName = displayName
    }

    public static let defaultFiles = [
        TerminalConfigurationFileSpec(relativePath: ".zshrc", displayName: "zshrc"),
        TerminalConfigurationFileSpec(relativePath: ".zprofile", displayName: "zprofile"),
        TerminalConfigurationFileSpec(relativePath: ".zlogin", displayName: "zlogin"),
        TerminalConfigurationFileSpec(relativePath: ".zlogout", displayName: "zlogout"),
        TerminalConfigurationFileSpec(relativePath: ".bash_profile", displayName: "bash_profile"),
        TerminalConfigurationFileSpec(relativePath: ".bashrc", displayName: "bashrc"),
        TerminalConfigurationFileSpec(relativePath: ".profile", displayName: "profile"),
        TerminalConfigurationFileSpec(relativePath: ".config/fish/config.fish", displayName: "fish config")
    ]

    var keyComponent: String {
        let components = relativePath
            .split { !$0.isLetter && !$0.isNumber }
            .map { $0.lowercased() }
        return components.isEmpty ? "unknown" : components.joined(separator: "-")
    }

    func snapshotItem(
        status: TerminalConfigurationStatus,
        lineCount: Int,
        findingCount: Int,
        ruleIDs: [String]
    ) -> SnapshotItem {
        var object = [
            "path": relativePath,
            "displayName": displayName,
            "status": status.rawValue,
            "lineCount": String(lineCount),
            "secretFindingCount": String(findingCount)
        ]
        if !ruleIDs.isEmpty {
            object["secretRules"] = ruleIDs.joined(separator: ",")
        }

        return SnapshotItem(
            key: "terminal.config.\(keyComponent)",
            value: .object(object),
            classification: status.classification,
            applicability: .userSpecific
        )
    }
}

public enum TerminalConfigurationStatus: String, Equatable, Sendable {
    case absent
    case metadataCaptured = "metadata-captured"
    case redacted
    case unreadable

    var classification: ConfigurationClassification {
        switch self {
        case .absent, .metadataCaptured:
            .safeConfiguration
        case .redacted:
            .potentiallySensitive
        case .unreadable:
            .userMustReview
        }
    }
}

struct TerminalConfigurationScanResult: Equatable, Sendable {
    var item: SnapshotItem
    var warnings: [SnapshotWarning]
}
