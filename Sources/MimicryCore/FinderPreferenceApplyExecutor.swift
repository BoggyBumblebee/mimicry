import Foundation

public struct FinderPreferenceApplySummary: Equatable, Sendable {
    public var backupURL: URL?
    public var results: [ApplyResult]

    public init(backupURL: URL?, results: [ApplyResult]) {
        self.backupURL = backupURL
        self.results = results
    }
}

public struct FinderPreferenceApplyExecutor: Sendable {
    public typealias DateProvider = @Sendable () -> Date

    private let runner: CommandRunner
    private let paths: SnapshotProviderToolPaths
    private let backupDirectory: URL
    private let dateProvider: DateProvider

    public init(
        runner: CommandRunner = ProcessCommandRunner(),
        paths: SnapshotProviderToolPaths = .macOSDefault,
        backupDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Mimicry", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true),
        dateProvider: @escaping DateProvider = Date.init
    ) {
        self.runner = runner
        self.paths = paths
        self.backupDirectory = backupDirectory
        self.dateProvider = dateProvider
    }

    public func apply(reference: MimicrySnapshot, current: MimicrySnapshot) async throws -> FinderPreferenceApplySummary {
        let finderDiff = SnapshotDiffEngine()
            .diff(reference: reference, current: current)
            .sections
            .first { $0.identifier == "finder" }
        let actions = finderDiff?.items.compactMap(applicableAction) ?? []

        guard !actions.isEmpty else {
            return FinderPreferenceApplySummary(backupURL: nil, results: [])
        }

        let backupURL = try writeBackup(current: current)
        var results: [ApplyResult] = []

        for action in actions {
            results.append(try await apply(action))
        }

        return FinderPreferenceApplySummary(backupURL: backupURL, results: results)
    }

    private func applicableAction(for item: SnapshotItemDiff) -> FinderPreferenceWriteAction? {
        guard item.status == .changed || item.status == .missing else {
            return nil
        }
        guard item.classification == .safeConfiguration else {
            return nil
        }
        guard item.key.hasPrefix("finder.") else {
            return nil
        }
        guard let value = item.referenceValue else {
            return nil
        }

        let key = String(item.key.dropFirst("finder.".count))
        switch value {
        case let .bool(value):
            return FinderPreferenceWriteAction(key: key, value: .bool(value))
        case let .string(value):
            return FinderPreferenceWriteAction(key: key, value: .string(value))
        case .absent, .double, .int, .object, .stringArray:
            return nil
        }
    }

    private func apply(_ action: FinderPreferenceWriteAction) async throws -> ApplyResult {
        let result = try await runner.run(
            executable: paths.defaults,
            arguments: action.arguments,
            environment: nil
        )

        return ApplyResult(
            actionID: UUID(),
            status: result.exitCode == 0 ? .success : .warning,
            message: result.exitCode == 0
                ? "Applied Finder preference \(action.key)."
                : "Finder preference \(action.key) could not be applied: \(result.standardError)"
        )
    }

    private func writeBackup(current: MimicrySnapshot) throws -> URL {
        let section = current.sections.first { $0.identifier == "finder" } ?? SnapshotSection(
            identifier: "finder",
            displayName: "Finder"
        )
        try FileManager.default.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true
        )

        let timestamp = Int(dateProvider().timeIntervalSince1970)
        let backupURL = backupDirectory.appendingPathComponent("finder-\(timestamp).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(section).write(to: backupURL, options: .atomic)
        return backupURL
    }
}

private struct FinderPreferenceWriteAction: Equatable, Sendable {
    var key: String
    var value: FinderPreferenceWriteValue

    var arguments: [String] {
        switch value {
        case let .bool(value):
            return ["write", FinderPreferenceDomain.finder.rawValue, key, "-bool", value ? "true" : "false"]
        case let .string(value):
            return ["write", FinderPreferenceDomain.finder.rawValue, key, value]
        }
    }
}

private enum FinderPreferenceWriteValue: Equatable, Sendable {
    case bool(Bool)
    case string(String)
}
