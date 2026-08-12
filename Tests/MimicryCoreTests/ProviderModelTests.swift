import MimicryCore
import XCTest

final class ProviderModelTests: XCTestCase {
    func testProviderCapabilitiesDefaultToDetectionAndPlanningButNotApply() {
        let capabilities = ProviderCapabilities()

        XCTAssertTrue(capabilities.canDetect)
        XCTAssertTrue(capabilities.canSnapshot)
        XCTAssertTrue(capabilities.canValidate)
        XCTAssertTrue(capabilities.canPlanApply)
        XCTAssertFalse(capabilities.canApply)
    }

    func testProviderContextsRetainCommandRunnerAndDryRunState() async throws {
        let runner = FakeCommandRunner()
        let detectionContext = DetectionContext(commandRunner: runner)
        let snapshotContext = SnapshotContext(commandRunner: runner)
        let applyContext = ApplyContext(commandRunner: runner)
        let explicitApplyContext = ApplyContext(commandRunner: runner, dryRun: false)

        _ = try await detectionContext.commandRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/detect"),
            arguments: [],
            environment: nil
        )
        _ = try await snapshotContext.commandRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/snapshot"),
            arguments: [],
            environment: nil
        )
        _ = try await applyContext.commandRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/apply"),
            arguments: [],
            environment: nil
        )

        let invocations = await runner.invocations
        XCTAssertEqual(invocations.map(\.executable), [
            "/usr/bin/detect",
            "/usr/bin/snapshot",
            "/usr/bin/apply"
        ])
        XCTAssertTrue(applyContext.dryRun)
        XCTAssertFalse(explicitApplyContext.dryRun)
    }

    func testProviderResultsAndPlannedActionsKeepValues() {
        let actionID = UUID(uuidString: "83C43290-2F1D-48A7-9414-6886303A0124")!
        let detection = DetectionResult(providerIdentifier: "homebrew", status: .success, message: "available")
        let validation = ValidationResult(status: .warning, messages: ["mas missing"])
        let emptyValidation = ValidationResult(status: .success)
        let action = PlannedAction(
            id: actionID,
            providerIdentifier: "homebrew",
            kind: .install,
            summary: "Install wget",
            requiresElevation: false
        )
        let result = ApplyResult(actionID: actionID, status: .skipped, message: "dry run")

        XCTAssertEqual(detection.providerIdentifier, "homebrew")
        XCTAssertEqual(detection.status, .success)
        XCTAssertEqual(detection.message, "available")
        XCTAssertEqual(validation.messages, ["mas missing"])
        XCTAssertEqual(emptyValidation.messages, [])
        XCTAssertEqual(action.id, actionID)
        XCTAssertEqual(action.kind, .install)
        XCTAssertEqual(action.summary, "Install wget")
        XCTAssertFalse(action.requiresElevation)
        XCTAssertEqual(result.actionID, actionID)
        XCTAssertEqual(result.status, .skipped)
        XCTAssertEqual(result.message, "dry run")
    }
}
