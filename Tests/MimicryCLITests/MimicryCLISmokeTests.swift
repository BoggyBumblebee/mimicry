@testable import MimicryCLISupport
import MimicryCore
import XCTest

final class MimicryCLISmokeTests: XCTestCase {
    func testDoctorOutputRendersCapabilityFindingsWithoutMutatingSystemState() {
        let output = MimicryCLIResponses.doctor(
            capabilities: MacCapabilities(
                environment: MacEnvironment(
                    macOSVersion: "Version 26.0",
                    architecture: .arm64,
                    hardwareModel: "MacBookPro18,3",
                    hostname: "reference-mac.local",
                    username: "cmb"
                ),
                security: MacSecurityCapabilities(
                    hasAdministratorPrivileges: true,
                    fileVaultState: .enabled,
                    sipState: .enabled
                ),
                tools: MacToolCapabilities(
                    hasCommandLineTools: true,
                    xcodeVersion: "Xcode 26.0",
                    homebrew: HomebrewCapability(
                        isInstalled: true,
                        prefix: "/opt/homebrew",
                        version: "Homebrew 5.0.0",
                        architecture: .arm64
                    ),
                    hasMAS: false
                ),
                services: MacServiceCapabilities(
                    iCloudState: .requiresUserAction,
                    appStoreState: .available,
                    managementState: .unknown
                ),
            )
        )

        XCTAssertTrue(output.contains("Mimicry Doctor"))
        XCTAssertTrue(output.contains("[PASS] Command Line Tools"))
        XCTAssertTrue(output.contains("[PASS] Homebrew"))
        XCTAssertTrue(output.contains("[WARN] mas CLI"))
        XCTAssertTrue(output.contains("[WARN] iCloud"))
        XCTAssertTrue(output.contains("No system settings were changed."))
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

    func testSnapshotResponseSummarizesCreatedPackage() {
        let package = MimicryPackage(
            url: URL(fileURLWithPath: "target.mimicry"),
            manifest: MimicryPackageManifest(),
            snapshot: MimicrySnapshot.phaseOneCLIFixture()
        )
        let output = MimicryCLIResponses.snapshot(package: package)

        XCTAssertTrue(output.contains("Mimicry Snapshot Created"))
        XCTAssertTrue(output.contains("target.mimicry"))
        XCTAssertTrue(output.contains("Sections: 1"))
        XCTAssertTrue(output.contains("No system settings were changed."))
    }

    func testPlaceholderCommandsNameRequestedSnapshotPath() {
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
