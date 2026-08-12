import MimicryCore
import XCTest

final class FinderSnapshotProviderTests: XCTestCase {
    func testSnapshotCapturesFinderPreferences() async throws {
        let provider = FinderSnapshotProvider(preferences: [
            FinderPreferenceSpec(key: "AppleShowAllFiles", valueKind: .bool),
            FinderPreferenceSpec(key: "ShowPathbar", valueKind: .bool),
            FinderPreferenceSpec(key: "FXPreferredViewStyle", valueKind: .string),
            FinderPreferenceSpec(
                key: "NewWindowTargetPath",
                valueKind: .string,
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ])
        let runner = FakeCommandRunner(results: [
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "1\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "false\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "Nlsv\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "file:///Users/cmb/Desktop/\n")
        ])

        let section = try await provider.snapshot(context: SnapshotContext(commandRunner: runner))

        XCTAssertEqual(section.identifier, "finder")
        XCTAssertEqual(section.warnings, [])
        XCTAssertTrue(section.items.contains(SnapshotItem(key: "finder.AppleShowAllFiles", value: .bool(true))))
        XCTAssertTrue(section.items.contains(SnapshotItem(key: "finder.ShowPathbar", value: .bool(false))))
        XCTAssertTrue(section.items.contains(SnapshotItem(key: "finder.FXPreferredViewStyle", value: .string("Nlsv"))))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "finder.NewWindowTargetPath",
                value: .string("file:///Users/cmb/Desktop/"),
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ))

        let invocations = await runner.invocations
        XCTAssertEqual(
            invocations.map(\.arguments),
            [
                ["read", "com.apple.finder", "AppleShowAllFiles"],
                ["read", "com.apple.finder", "ShowPathbar"],
                ["read", "com.apple.finder", "FXPreferredViewStyle"],
                ["read", "com.apple.finder", "NewWindowTargetPath"]
            ]
        )
    }

    func testSnapshotMarksMissingPreferenceAbsentWithoutWarning() async throws {
        let provider = FinderSnapshotProvider(preferences: [
            FinderPreferenceSpec(key: "ShowStatusBar", valueKind: .bool)
        ])
        let runner = FakeCommandRunner(results: [
            CommandResult(
                executable: "",
                arguments: [],
                exitCode: 1,
                standardError: "The domain/default pair of (com.apple.finder, ShowStatusBar) does not exist"
            )
        ])

        let section = try await provider.snapshot(context: SnapshotContext(commandRunner: runner))

        XCTAssertEqual(section.items, [
            SnapshotItem(key: "finder.ShowStatusBar", value: .absent)
        ])
        XCTAssertEqual(section.warnings, [])
    }

    func testSnapshotWarnsWhenPreferenceCannotBeRead() async throws {
        let provider = FinderSnapshotProvider(preferences: [
            FinderPreferenceSpec(key: "ShowStatusBar", valueKind: .bool)
        ])
        let runner = FakeCommandRunner(results: [
            CommandResult(executable: "", arguments: [], exitCode: 1, standardError: "permission denied")
        ])

        let section = try await provider.snapshot(context: SnapshotContext(commandRunner: runner))

        XCTAssertEqual(section.items, [
            SnapshotItem(key: "finder.ShowStatusBar", value: .absent)
        ])
        XCTAssertEqual(section.warnings.map(\.code), ["finder.preference-unreadable.ShowStatusBar"])
    }

    func testDetectReportsFinderPreferenceAvailability() async throws {
        let available = try await FinderSnapshotProvider().detect(
            context: DetectionContext(commandRunner: FakeCommandRunner(results: [
                CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "{ }")
            ]))
        )
        let unavailable = try await FinderSnapshotProvider().detect(
            context: DetectionContext(commandRunner: FakeCommandRunner(results: [
                CommandResult(executable: "", arguments: [], exitCode: 1, standardError: "domain missing")
            ]))
        )

        XCTAssertEqual(available.status, .success)
        XCTAssertEqual(unavailable.status, .warning)
    }

    func testProviderLifecycleMethodsDeferApplyToLaterPhase() async throws {
        let provider = FinderSnapshotProvider()
        let valid = try await provider.validate(
            section: SnapshotSection(identifier: "finder", displayName: "Finder"),
            context: ValidationContext()
        )
        let invalid = try await provider.validate(
            section: SnapshotSection(identifier: "other", displayName: "Other"),
            context: ValidationContext()
        )
        let actions = try await provider.planApply(
            section: SnapshotSection(identifier: "finder", displayName: "Finder"),
            context: ApplyContext(commandRunner: FakeCommandRunner())
        )
        let result = try await provider.apply(
            action: actions[0],
            context: ApplyContext(commandRunner: FakeCommandRunner())
        )

        XCTAssertEqual(valid.status, .success)
        XCTAssertEqual(invalid.status, .warning)
        XCTAssertEqual(actions.map(\.kind), [.requiresUserAction])
        XCTAssertEqual(result.status, .skipped)
    }
}
