import Foundation

public struct HomebrewSnapshotProvider: ConfigurationProvider {
    public let identifier = "homebrew"
    public let displayName = "Homebrew"
    public let capabilities = ProviderCapabilities(canApply: false)

    private let paths: SnapshotProviderToolPaths

    public init(paths: SnapshotProviderToolPaths = .macOSDefault) {
        self.paths = paths
    }

    public func detect(context: DetectionContext) async throws -> DetectionResult {
        let result = try await context.commandRunner.run(
            executable: paths.env,
            arguments: ["brew", "--prefix"],
            environment: nil
        )

        return DetectionResult(
            providerIdentifier: identifier,
            status: result.exitCode == 0 ? .success : .warning,
            message: result.exitCode == 0 ? "Homebrew is available." : "Homebrew was not detected."
        )
    }

    public func snapshot(context: SnapshotContext) async throws -> SnapshotSection {
        let prefixResult = try await brew(["--prefix"], context: context)
        guard prefixResult.exitCode == 0, let prefix = prefixResult.standardOutput.trimmedNilIfEmpty else {
            return SnapshotSection(
                identifier: identifier,
                displayName: displayName,
                items: [
                    SnapshotItem(key: "homebrew.installed", value: .bool(false))
                ],
                warnings: [
                    SnapshotWarning(
                        code: "homebrew.unavailable",
                        message: "Homebrew was not detected; taps, formulae, and casks were not captured."
                    )
                ]
            )
        }

        let versionResult = try await brew(["--version"], context: context)
        let tapsResult = try await brew(["tap"], context: context)
        let formulaeResult = try await brew(["list", "--formula", "--versions"], context: context)
        let casksResult = try await brew(["list", "--cask", "--versions"], context: context)

        var items = [
            SnapshotItem(key: "homebrew.installed", value: .bool(true)),
            SnapshotItem(key: "homebrew.prefix", value: .string(prefix), classification: .machineSpecific),
            SnapshotItem(key: "homebrew.architecture", value: .string(homebrewArchitecture(prefix: prefix).rawValue)),
            SnapshotItem(key: "homebrew.version", value: firstLine(versionResult.standardOutput).map(SnapshotValue.string) ?? .absent)
        ]

        items += parsePlainLines(tapsResult.standardOutput).map {
            SnapshotItem(key: "homebrew.tap.\($0)", value: .string($0))
        }
        items += parseVersionedLines(formulaeResult.standardOutput).map {
            SnapshotItem(key: "homebrew.formula.\($0.name)", value: .object(["name": $0.name, "version": $0.version]))
        }
        items += parseVersionedLines(casksResult.standardOutput).map {
            SnapshotItem(key: "homebrew.cask.\($0.name)", value: .object(["name": $0.name, "version": $0.version]))
        }

        return SnapshotSection(
            identifier: identifier,
            displayName: displayName,
            items: items,
            warnings: warnings(for: [
                ("homebrew.version-unavailable", versionResult),
                ("homebrew.taps-unavailable", tapsResult),
                ("homebrew.formulae-unavailable", formulaeResult),
                ("homebrew.casks-unavailable", casksResult)
            ])
        )
    }

    public func validate(section: SnapshotSection, context: ValidationContext) async throws -> ValidationResult {
        section.identifier == identifier
            ? ValidationResult(status: .success)
            : ValidationResult(status: .warning, messages: ["Expected Homebrew section."])
    }

    public func planApply(section: SnapshotSection, context: ApplyContext) async throws -> [PlannedAction] {
        [
            PlannedAction(
                providerIdentifier: identifier,
                kind: .requiresUserAction,
                summary: "Homebrew apply planning starts in Phase 5."
            )
        ]
    }

    public func apply(action: PlannedAction, context: ApplyContext) async throws -> ApplyResult {
        ApplyResult(actionID: action.id, status: .skipped, message: "Homebrew apply is not implemented yet.")
    }

    private func brew(_ arguments: [String], context: SnapshotContext) async throws -> CommandResult {
        try await context.commandRunner.run(
            executable: paths.env,
            arguments: ["brew"] + arguments,
            environment: nil
        )
    }

    private func warnings(for results: [(String, CommandResult)]) -> [SnapshotWarning] {
        results.compactMap { code, result in
            result.exitCode == 0
                ? nil
                : SnapshotWarning(code: code, message: "`brew \(result.arguments.dropFirst().joined(separator: " "))` did not complete successfully.")
        }
    }

    private func homebrewArchitecture(prefix: String) -> MacArchitecture {
        switch prefix {
        case SystemToolPathFactory.absoluteURL(["opt", "homebrew"]).path:
            .arm64
        case SystemToolPathFactory.absoluteURL(["usr", "local"]).path:
            .x86_64
        default:
            .unknown
        }
    }
}

private struct VersionedPackage: Equatable {
    var name: String
    var version: String
}

private func parsePlainLines(_ output: String) -> [String] {
    output
        .split(separator: "\n")
        .map(String.init)
        .compactMap(\.trimmedNilIfEmpty)
        .sorted()
}

private func parseVersionedLines(_ output: String) -> [VersionedPackage] {
    output
        .split(separator: "\n")
        .compactMap { line -> VersionedPackage? in
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard let name = parts.first.map(String.init)?.trimmedNilIfEmpty else {
                return nil
            }
            let version = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return VersionedPackage(name: name, version: version)
        }
        .sorted { $0.name < $1.name }
}

private func firstLine(_ output: String) -> String? {
    output
        .split(separator: "\n")
        .first
        .map(String.init)?
        .trimmedNilIfEmpty
}
