import Foundation

public struct AppStoreSnapshotProvider: ConfigurationProvider {
    public let identifier = "app-store"
    public let displayName = "App Store"
    public let capabilities = ProviderCapabilities(canApply: false)

    private let paths: SnapshotProviderToolPaths

    public init(paths: SnapshotProviderToolPaths = .macOSDefault) {
        self.paths = paths
    }

    public func detect(context: DetectionContext) async throws -> DetectionResult {
        let command = try await resolveMAS(context: context)

        return DetectionResult(
            providerIdentifier: identifier,
            status: command == nil ? .warning : .success,
            message: command == nil ? "`mas` was not detected." : "`mas` is available."
        )
    }

    public func snapshot(context: SnapshotContext) async throws -> SnapshotSection {
        guard let masCommand = try await resolveMAS(context: context) else {
            return SnapshotSection(
                identifier: identifier,
                displayName: displayName,
                items: [
                    SnapshotItem(key: "app-store.mas-available", value: .bool(false))
                ],
                warnings: [
                    SnapshotWarning(
                        code: "app-store.mas-unavailable",
                        message: "`mas` was not available; App Store applications were not captured."
                    )
                ]
            )
        }

        let listResult = try await masCommand.run(["list"], context: context)
        guard listResult.exitCode == 0 else {
            return SnapshotSection(
                identifier: identifier,
                displayName: displayName,
                items: [
                    SnapshotItem(key: "app-store.mas-available", value: .bool(true))
                ],
                warnings: [
                    SnapshotWarning(
                        code: "app-store.inventory-unavailable",
                        message: "`mas list` did not complete successfully; App Store applications were not captured."
                    )
                ]
            )
        }

        let apps = parseMASList(listResult.standardOutput)
        let items = [SnapshotItem(key: "app-store.mas-available", value: .bool(true))]
            + apps.map { app in
                SnapshotItem(
                    key: "app-store.app.\(app.identifier)",
                    value: .object([
                        "identifier": app.identifier,
                        "name": app.name,
                        "version": app.version
                    ]),
                    applicability: .userSpecific
                )
            }

        return SnapshotSection(identifier: identifier, displayName: displayName, items: items)
    }

    public func validate(section: SnapshotSection, context _: ValidationContext) async throws -> ValidationResult {
        section.identifier == identifier
            ? ValidationResult(status: .success)
            : ValidationResult(status: .warning, messages: ["Expected App Store section."])
    }

    public func planApply(section _: SnapshotSection, context _: ApplyContext) async throws -> [PlannedAction] {
        [
            PlannedAction(
                providerIdentifier: identifier,
                kind: .requiresUserAction,
                summary: "App Store apply planning starts in Phase 5 and may require App Store sign-in."
            )
        ]
    }

    public func apply(action: PlannedAction, context _: ApplyContext) async throws -> ApplyResult {
        ApplyResult(actionID: action.id, status: .skipped, message: "App Store apply is not implemented yet.")
    }

    private func resolveMAS(context: DetectionContext) async throws -> MASCommand? {
        try await resolveMAS { executable, arguments in
            try await context.commandRunner.run(
                executable: executable,
                arguments: arguments,
                environment: nil
            )
        }
    }

    private func resolveMAS(context: SnapshotContext) async throws -> MASCommand? {
        try await resolveMAS { executable, arguments in
            try await context.commandRunner.run(
                executable: executable,
                arguments: arguments,
                environment: nil
            )
        }
    }

    private func resolveMAS(
        run: (URL, [String]) async throws -> CommandResult
    ) async throws -> MASCommand? {
        let shellResult = try await run(paths.env, ["mas", "version"])
        if shellResult.exitCode == 0 {
            return MASCommand(executable: paths.env, argumentPrefix: ["mas"])
        }

        for candidate in paths.masExecutableCandidates {
            let result = try await run(candidate, ["version"])
            if result.exitCode == 0 {
                return MASCommand(executable: candidate, argumentPrefix: [])
            }
        }

        return nil
    }
}

private struct MASCommand {
    var executable: URL
    var argumentPrefix: [String]

    func run(_ arguments: [String], context: SnapshotContext) async throws -> CommandResult {
        try await context.commandRunner.run(
            executable: executable,
            arguments: argumentPrefix + arguments,
            environment: nil
        )
    }
}

private struct MASApplication: Equatable {
    var identifier: String
    var name: String
    var version: String
}

private func parseMASList(_ output: String) -> [MASApplication] {
    output
        .split(separator: "\n")
        .compactMap { line -> MASApplication? in
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard parts.count == 2 else {
                return nil
            }

            let identifier = String(parts[0])
            let remainder = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                let openParen = remainder.lastIndex(of: "("),
                remainder.hasSuffix(")")
            else {
                return MASApplication(identifier: identifier, name: remainder, version: "")
            }

            let name = remainder[..<openParen].trimmingCharacters(in: .whitespacesAndNewlines)
            let versionStart = remainder.index(after: openParen)
            let versionEnd = remainder.index(before: remainder.endIndex)
            return MASApplication(
                identifier: identifier,
                name: String(name),
                version: String(remainder[versionStart..<versionEnd])
            )
        }
        .sorted { $0.name < $1.name }
}
