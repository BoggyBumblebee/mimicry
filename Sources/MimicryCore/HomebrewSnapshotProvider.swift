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
        let result = try await resolveBrew(context: context)

        return DetectionResult(
            providerIdentifier: identifier,
            status: result == nil ? .warning : .success,
            message: result == nil ? "Homebrew was not detected." : "Homebrew is available."
        )
    }

    public func snapshot(context: SnapshotContext) async throws -> SnapshotSection {
        guard let brewCommand = try await resolveBrew(context: context),
              let prefix = brewCommand.prefixResult.standardOutput.trimmedNilIfEmpty else {
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

        let versionResult = try await brewCommand.run(["--version"], context: context)
        let tapsResult = try await brewCommand.run(["tap"], context: context)
        let formulaeResult = try await brewCommand.run(["list", "--formula", "--versions"], context: context)
        let casksResult = try await brewCommand.run(["list", "--cask", "--versions"], context: context)

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

    public func validate(section: SnapshotSection, context _: ValidationContext) async throws -> ValidationResult {
        section.identifier == identifier
            ? ValidationResult(status: .success)
            : ValidationResult(status: .warning, messages: ["Expected Homebrew section."])
    }

    public func planApply(section _: SnapshotSection, context _: ApplyContext) async throws -> [PlannedAction] {
        [
            PlannedAction(
                providerIdentifier: identifier,
                kind: .requiresUserAction,
                summary: "Homebrew apply planning starts in Phase 5."
            )
        ]
    }

    public func apply(action: PlannedAction, context _: ApplyContext) async throws -> ApplyResult {
        ApplyResult(actionID: action.id, status: .skipped, message: "Homebrew apply is not implemented yet.")
    }

    private func resolveBrew(context: DetectionContext) async throws -> HomebrewCommand? {
        try await resolveBrew { executable, arguments in
            try await context.commandRunner.run(
                executable: executable,
                arguments: arguments,
                environment: nil
            )
        }
    }

    private func resolveBrew(context: SnapshotContext) async throws -> HomebrewCommand? {
        try await resolveBrew { executable, arguments in
            try await context.commandRunner.run(
                executable: executable,
                arguments: arguments,
                environment: nil
            )
        }
    }

    private func resolveBrew(
        run: (URL, [String]) async throws -> CommandResult
    ) async throws -> HomebrewCommand? {
        let shellResult = try await run(paths.env, ["brew", "--prefix"])
        if shellResult.exitCode == 0 {
            return HomebrewCommand(executable: paths.env, argumentPrefix: ["brew"], prefixResult: shellResult)
        }

        for candidate in paths.homebrewExecutableCandidates {
            let result = try await run(candidate, ["--prefix"])
            if result.exitCode == 0 {
                return HomebrewCommand(executable: candidate, argumentPrefix: [], prefixResult: result)
            }
        }

        return nil
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

private struct HomebrewCommand {
    var executable: URL
    var argumentPrefix: [String]
    var prefixResult: CommandResult

    func run(_ arguments: [String], context: SnapshotContext) async throws -> CommandResult {
        try await context.commandRunner.run(
            executable: executable,
            arguments: argumentPrefix + arguments,
            environment: nil
        )
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
