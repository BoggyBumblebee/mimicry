@testable import MimicryCLISupport
import MimicryCore
import XCTest

final class MimicryCLISmokeTests: XCTestCase {
    func testDoctorOutputIsExplicitlyNonMutatingScaffold() {
        let output = MimicryCLIResponses.doctor()

        XCTAssertTrue(output.contains("Mimicry Doctor"))
        XCTAssertTrue(output.contains("Phase 1 scaffold only"))
        XCTAssertTrue(output.contains("No system checks have been implemented yet."))
    }

    func testRootCommandExposesExpectedSubcommands() {
        XCTAssertEqual(
            MimicryCLIResponses.phaseOneSubcommandNames,
            ["doctor", "snapshot", "inspect", "validate", "diff", "apply"]
        )
    }

    func testInspectAndValidateReadPackageWithoutMutatingSystemState() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let packageURL = temporaryDirectory.appendingPathComponent("fixture.mimicry")
        let snapshot = MimicrySnapshot.phaseOneCLIFixture()
        _ = try MimicryPackageStore().write(snapshot: snapshot, to: packageURL)

        let inspectOutput = try MimicryCLIResponses.inspect(packagePath: packageURL.path)
        let validateOutput = try MimicryCLIResponses.validate(packagePath: packageURL.path)

        XCTAssertTrue(inspectOutput.contains("Mimicry Snapshot"))
        XCTAssertTrue(inspectOutput.contains("Schema version: 1"))
        XCTAssertTrue(inspectOutput.contains("Sections: 1"))
        XCTAssertEqual(validateOutput, "Validation passed.")
    }

    func testPlaceholderCommandsNameRequestedSnapshotPath() {
        XCTAssertTrue(MimicryCLIResponses.snapshot(output: "target.mimicry").contains("target.mimicry"))
        XCTAssertTrue(MimicryCLIResponses.diff(packagePath: "target.mimicry").contains("target.mimicry"))
        XCTAssertTrue(MimicryCLIResponses.apply(packagePath: "target.mimicry", dryRun: true).contains("Dry run: true"))
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
    static func phaseOneCLIFixture() -> MimicrySnapshot {
        MimicrySnapshot(
            mimicryVersion: "0.1.0",
            createdAt: Date(timeIntervalSince1970: 1_786_492_800),
            source: SnapshotSource(
                macOSVersion: "26.0",
                architecture: "arm64",
                hardwareModel: "MacBookPro",
                hostname: "reference-mac",
                username: "cmb"
            ),
            sections: [
                SnapshotSection(
                    identifier: "environment",
                    displayName: "Environment",
                    capturedAt: Date(timeIntervalSince1970: 1_786_492_800),
                    items: [
                        SnapshotItem(key: "architecture", value: .string("arm64"))
                    ]
                )
            ]
        )
    }
}
