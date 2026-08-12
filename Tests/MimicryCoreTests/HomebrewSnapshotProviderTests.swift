import MimicryCore
import XCTest

final class HomebrewSnapshotProviderTests: XCTestCase {
    func testSnapshotCapturesHomebrewInventory() async throws {
        let runner = FakeCommandRunner(results: [
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "/opt/homebrew\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "Homebrew 5.0.0\nHomebrew/homebrew-core 5.0.0\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "homebrew/core\nboggy/tools\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "swiftlint 0.59.0\nopenssl@3 3.5.1\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "visual-studio-code 1.102.3\n")
        ])
        let section = try await HomebrewSnapshotProvider().snapshot(
            context: SnapshotContext(commandRunner: runner)
        )

        XCTAssertEqual(section.identifier, "homebrew")
        XCTAssertEqual(section.warnings, [])
        XCTAssertTrue(section.items.contains(SnapshotItem(key: "homebrew.installed", value: .bool(true))))
        XCTAssertTrue(section.items.contains(SnapshotItem(key: "homebrew.prefix", value: .string("/opt/homebrew"), classification: .machineSpecific)))
        XCTAssertTrue(section.items.contains(SnapshotItem(key: "homebrew.architecture", value: .string("arm64"))))
        XCTAssertTrue(section.items.contains(SnapshotItem(key: "homebrew.version", value: .string("Homebrew 5.0.0"))))
        XCTAssertTrue(section.items.contains(SnapshotItem(key: "homebrew.tap.boggy/tools", value: .string("boggy/tools"))))
        XCTAssertTrue(section.items.contains(SnapshotItem(key: "homebrew.formula.openssl@3", value: .object(["name": "openssl@3", "version": "3.5.1"]))))
        XCTAssertTrue(section.items.contains(SnapshotItem(key: "homebrew.cask.visual-studio-code", value: .object(["name": "visual-studio-code", "version": "1.102.3"]))))

        let invocations = await runner.invocations
        XCTAssertEqual(
            invocations.map(\.arguments),
            [
                ["brew", "--prefix"],
                ["brew", "--version"],
                ["brew", "tap"],
                ["brew", "list", "--formula", "--versions"],
                ["brew", "list", "--cask", "--versions"]
            ]
        )
    }

    func testSnapshotWarnsWhenHomebrewIsUnavailable() async throws {
        let runner = FakeCommandRunner(results: [
            CommandResult(executable: "", arguments: [], exitCode: 1, standardError: "brew not found")
        ])

        let section = try await HomebrewSnapshotProvider().snapshot(
            context: SnapshotContext(commandRunner: runner)
        )

        XCTAssertEqual(section.items, [
            SnapshotItem(key: "homebrew.installed", value: .bool(false))
        ])
        XCTAssertEqual(section.warnings.map(\.code), ["homebrew.unavailable"])
    }

    func testSnapshotKeepsPartialInventoryWhenOneBrewCommandFails() async throws {
        let runner = FakeCommandRunner(results: [
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "/usr/local\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "Homebrew 5.0.0\n"),
            CommandResult(executable: "", arguments: [], exitCode: 1, standardError: "tap failed"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "git 2.50.0\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "")
        ])

        let section = try await HomebrewSnapshotProvider().snapshot(
            context: SnapshotContext(commandRunner: runner)
        )

        XCTAssertTrue(section.items.contains(SnapshotItem(key: "homebrew.architecture", value: .string("x86_64"))))
        XCTAssertTrue(section.items.contains(SnapshotItem(key: "homebrew.formula.git", value: .object(["name": "git", "version": "2.50.0"]))))
        XCTAssertEqual(section.warnings.map(\.code), ["homebrew.taps-unavailable"])
    }

    func testDetectReportsAvailability() async throws {
        let available = try await HomebrewSnapshotProvider().detect(
            context: DetectionContext(commandRunner: FakeCommandRunner(results: [
                CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "/opt/homebrew\n")
            ]))
        )
        let unavailable = try await HomebrewSnapshotProvider().detect(
            context: DetectionContext(commandRunner: FakeCommandRunner(results: [
                CommandResult(executable: "", arguments: [], exitCode: 1, standardError: "brew not found")
            ]))
        )

        XCTAssertEqual(available.status, .success)
        XCTAssertEqual(unavailable.status, .warning)
    }

    func testProviderLifecycleMethodsDeferApplyToLaterPhase() async throws {
        let provider = HomebrewSnapshotProvider()
        let valid = try await provider.validate(
            section: SnapshotSection(identifier: "homebrew", displayName: "Homebrew"),
            context: ValidationContext()
        )
        let invalid = try await provider.validate(
            section: SnapshotSection(identifier: "other", displayName: "Other"),
            context: ValidationContext()
        )
        let actions = try await provider.planApply(
            section: SnapshotSection(identifier: "homebrew", displayName: "Homebrew"),
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
