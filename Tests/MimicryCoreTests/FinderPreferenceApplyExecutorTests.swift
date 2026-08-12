import MimicryCore
import XCTest

final class FinderPreferenceApplyExecutorTests: XCTestCase {
    func testApplyWritesOnlySafeChangedFinderPreferencesAndBacksUpCurrentSection() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let backupDirectory = temporaryDirectory.appendingPathComponent("Backups", isDirectory: true)
        let runner = FakeCommandRunner()
        let executor = FinderPreferenceApplyExecutor(
            runner: runner,
            paths: SnapshotProviderToolPaths(defaults: URL(fileURLWithPath: "defaults")),
            backupDirectory: backupDirectory,
            dateProvider: { Date(timeIntervalSince1970: 1_786_492_800) }
        )

        let summary = try await executor.apply(
            reference: .finderApplyReferenceFixture(),
            current: .finderApplyCurrentFixture()
        )

        let invocations = await runner.invocations
        XCTAssertEqual(summary.results.count, 2)
        XCTAssertEqual(summary.results.map(\.status), [.success, .success])
        XCTAssertEqual(invocations.map(\.arguments), [
            ["write", "com.apple.finder", "FXPreferredViewStyle", "Nlsv"],
            ["write", "com.apple.finder", "ShowPathbar", "-bool", "true"]
        ])

        let backupURL = try XCTUnwrap(summary.backupURL)
        XCTAssertEqual(backupURL.lastPathComponent, "finder-1786492800.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(
            SnapshotSection.self,
            from: Data(contentsOf: backupURL)
        )
        XCTAssertEqual(backup.identifier, "finder")
        XCTAssertEqual(backup.items.first { $0.key == "finder.ShowPathbar" }?.value, .bool(false))
    }

    func testApplyWithoutSafeFinderChangesDoesNotWriteBackupOrRunCommands() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let runner = FakeCommandRunner()
        let executor = FinderPreferenceApplyExecutor(
            runner: runner,
            paths: SnapshotProviderToolPaths(defaults: URL(fileURLWithPath: "defaults")),
            backupDirectory: temporaryDirectory
        )

        let snapshot = MimicrySnapshot.finderApplyReferenceFixture()
        let summary = try await executor.apply(reference: snapshot, current: snapshot)

        let invocations = await runner.invocations
        XCTAssertNil(summary.backupURL)
        XCTAssertTrue(summary.results.isEmpty)
        XCTAssertTrue(invocations.isEmpty)
        XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)).isEmpty)
    }

    func testFailedDefaultsWriteIsReportedAsWarning() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let runner = FakeCommandRunner(results: [
            CommandResult(
                executable: "",
                arguments: [],
                exitCode: 1,
                standardError: "permission denied"
            )
        ])
        let executor = FinderPreferenceApplyExecutor(
            runner: runner,
            paths: SnapshotProviderToolPaths(defaults: URL(fileURLWithPath: "defaults")),
            backupDirectory: temporaryDirectory
        )

        let reference = MimicrySnapshot.finderSnapshot(items: [
            SnapshotItem(key: "finder.ShowPathbar", value: .bool(true))
        ])
        let current = MimicrySnapshot.finderSnapshot(items: [
            SnapshotItem(key: "finder.ShowPathbar", value: .bool(false))
        ])
        let summary = try await executor.apply(reference: reference, current: current)

        XCTAssertEqual(summary.results.count, 1)
        XCTAssertEqual(summary.results.first?.status, .warning)
        XCTAssertTrue(summary.results.first?.message.contains("permission denied") == true)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}

private extension MimicrySnapshot {
    static func finderApplyReferenceFixture() -> MimicrySnapshot {
        finderSnapshot(items: [
            SnapshotItem(key: "finder.FXPreferredViewStyle", value: .string("Nlsv")),
            SnapshotItem(
                key: "finder.NewWindowTargetPath",
                value: .string("review-only-reference-path"),
                classification: .userMustReview,
                applicability: .userSpecific
            ),
            SnapshotItem(key: "finder.ShowPathbar", value: .bool(true)),
            SnapshotItem(key: "finder.WarnOnEmptyTrash", value: .absent)
        ])
    }

    static func finderApplyCurrentFixture() -> MimicrySnapshot {
        finderSnapshot(items: [
            SnapshotItem(key: "finder.FXPreferredViewStyle", value: .string("icnv")),
            SnapshotItem(
                key: "finder.NewWindowTargetPath",
                value: .string("review-only-current-path"),
                classification: .userMustReview,
                applicability: .userSpecific
            ),
            SnapshotItem(key: "finder.ShowPathbar", value: .bool(false)),
            SnapshotItem(key: "finder.WarnOnEmptyTrash", value: .bool(true))
        ])
    }

    static func finderSnapshot(items: [SnapshotItem]) -> MimicrySnapshot {
        MimicrySnapshot(
            mimicryVersion: "0.1.0",
            createdAt: Date(timeIntervalSince1970: 1_786_492_800),
            source: SnapshotSource(
                macOSVersion: "26.0",
                architecture: "arm64",
                hardwareModel: "MacBookPro",
                hostname: "test-mac",
                username: "cmb"
            ),
            sections: [
                SnapshotSection(
                    identifier: "finder",
                    displayName: "Finder",
                    capturedAt: Date(timeIntervalSince1970: 1_786_492_800),
                    items: items
                )
            ]
        )
    }
}
