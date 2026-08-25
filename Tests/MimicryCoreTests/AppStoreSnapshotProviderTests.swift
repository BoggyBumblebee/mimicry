import MimicryCore
import XCTest

final class AppStoreSnapshotProviderTests: XCTestCase {
    func testSnapshotCapturesMASApplications() async throws {
        let runner = FakeCommandRunner(results: [
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "7.0.0\n"),
            CommandResult(
                executable: "",
                arguments: [],
                exitCode: 0,
                standardOutput: """
                497799835 Xcode (16.4)
                1444383602 GoodNotes 6 (6.6.0)
                123456789 App With Parentheses (Mac) (1.2.3)
                """
            )
        ])

        let section = try await AppStoreSnapshotProvider().snapshot(
            context: SnapshotContext(commandRunner: runner)
        )

        XCTAssertEqual(section.identifier, "app-store")
        XCTAssertEqual(section.warnings, [])
        XCTAssertTrue(section.items.contains(SnapshotItem(key: "app-store.mas-available", value: .bool(true))))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "app-store.app.497799835",
                value: .object(["identifier": "497799835", "name": "Xcode", "version": "16.4"]),
                applicability: .userSpecific
            )
        ))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "app-store.app.123456789",
                value: .object(["identifier": "123456789", "name": "App With Parentheses (Mac)", "version": "1.2.3"]),
                applicability: .userSpecific
            )
        ))

        let invocations = await runner.invocations
        XCTAssertEqual(invocations.map(\.arguments), [["mas", "version"], ["mas", "list"]])
    }

    func testSnapshotFindsMASAtStandardPrefixWhenShellPathMissesMas() async throws {
        let runner = FakeCommandRunner(results: [
            CommandResult(executable: "", arguments: [], exitCode: 1, standardError: "mas not found"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "7.0.0\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "497799835 Xcode (16.4)\n")
        ])

        let section = try await AppStoreSnapshotProvider().snapshot(
            context: SnapshotContext(commandRunner: runner)
        )
        let invocations = await runner.invocations

        XCTAssertTrue(section.items.contains(SnapshotItem(key: "app-store.mas-available", value: .bool(true))))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "app-store.app.497799835",
                value: .object(["identifier": "497799835", "name": "Xcode", "version": "16.4"]),
                applicability: .userSpecific
            )
        ))
        XCTAssertEqual(invocations.map(\.executable), [
            "/usr/bin/env",
            "/opt/homebrew/bin/mas",
            "/opt/homebrew/bin/mas"
        ])
        XCTAssertEqual(invocations.map(\.arguments), [
            ["mas", "version"],
            ["version"],
            ["list"]
        ])
    }

    func testSnapshotWarnsWhenMASIsUnavailable() async throws {
        let runner = FakeCommandRunner(results: [
            CommandResult(executable: "", arguments: [], exitCode: 127, standardError: "mas not found"),
            CommandResult(executable: "", arguments: [], exitCode: 127, standardError: "mas not found"),
            CommandResult(executable: "", arguments: [], exitCode: 127, standardError: "mas not found")
        ])

        let section = try await AppStoreSnapshotProvider().snapshot(
            context: SnapshotContext(commandRunner: runner)
        )

        XCTAssertEqual(section.items, [
            SnapshotItem(key: "app-store.mas-available", value: .bool(false))
        ])
        XCTAssertEqual(section.warnings.map(\.code), ["app-store.mas-unavailable"])
    }

    func testSnapshotWarnsWhenMASInventoryFailsAfterToolResolution() async throws {
        let runner = FakeCommandRunner(results: [
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "7.0.0\n"),
            CommandResult(executable: "", arguments: [], exitCode: 124, standardError: "Command timed out after 30.0 seconds.")
        ])

        let section = try await AppStoreSnapshotProvider().snapshot(
            context: SnapshotContext(commandRunner: runner)
        )

        XCTAssertEqual(section.items, [
            SnapshotItem(key: "app-store.mas-available", value: .bool(true))
        ])
        XCTAssertEqual(section.warnings.map(\.code), ["app-store.inventory-unavailable"])
    }

    func testDetectReportsMASAvailability() async throws {
        let available = try await AppStoreSnapshotProvider().detect(
            context: DetectionContext(commandRunner: FakeCommandRunner(results: [
                CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "2.0.0\n")
            ]))
        )
        let unavailable = try await AppStoreSnapshotProvider().detect(
            context: DetectionContext(commandRunner: FakeCommandRunner(results: [
                CommandResult(executable: "", arguments: [], exitCode: 127, standardError: "mas not found"),
                CommandResult(executable: "", arguments: [], exitCode: 127, standardError: "mas not found"),
                CommandResult(executable: "", arguments: [], exitCode: 127, standardError: "mas not found")
            ]))
        )

        XCTAssertEqual(available.status, .success)
        XCTAssertEqual(unavailable.status, .warning)
    }

    func testProviderLifecycleMethodsDeferApplyToLaterPhase() async throws {
        let provider = AppStoreSnapshotProvider()
        let valid = try await provider.validate(
            section: SnapshotSection(identifier: "app-store", displayName: "App Store"),
            context: ValidationContext()
        )
        let invalid = try await provider.validate(
            section: SnapshotSection(identifier: "other", displayName: "Other"),
            context: ValidationContext()
        )
        let actions = try await provider.planApply(
            section: SnapshotSection(identifier: "app-store", displayName: "App Store"),
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
