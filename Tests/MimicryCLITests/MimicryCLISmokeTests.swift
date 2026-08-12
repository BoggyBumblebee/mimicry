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
        XCTAssertTrue(inspectOutput.contains("Source: reference-mac (cmb)"))
        XCTAssertTrue(inspectOutput.contains("Sections: 2"))
        XCTAssertTrue(inspectOutput.contains("Items: 6"))
        XCTAssertTrue(inspectOutput.contains("Warnings: 1"))
        XCTAssertTrue(inspectOutput.contains("Classification Summary"))
        XCTAssertTrue(inspectOutput.contains("- safe configuration: 1"))
        XCTAssertTrue(inspectOutput.contains("- excluded: 1"))
        XCTAssertTrue(inspectOutput.contains("- user must review: 1"))
        XCTAssertTrue(inspectOutput.contains("- machine specific: 1"))
        XCTAssertTrue(inspectOutput.contains("- unsupported: 1"))
        XCTAssertTrue(inspectOutput.contains("Applicability Summary"))
        XCTAssertTrue(inspectOutput.contains("- universal: 3"))
        XCTAssertTrue(inspectOutput.contains("- user specific: 3"))
        XCTAssertTrue(inspectOutput.contains("Environment (environment)"))
        XCTAssertTrue(inspectOutput.contains("Captured Items"))
        XCTAssertTrue(inspectOutput.contains("architecture = arm64 [safe configuration, universal]"))
        XCTAssertTrue(inspectOutput.contains("Review Required"))
        XCTAssertTrue(inspectOutput.contains("username = cmb [user must review, user specific]"))
        XCTAssertTrue(inspectOutput.contains("hostname = reference-mac [machine specific, universal]"))
        XCTAssertTrue(inspectOutput.contains("Excluded Items"))
        XCTAssertTrue(inspectOutput.contains("icloud.auth-state = excluded [excluded, user specific]"))
        XCTAssertTrue(inspectOutput.contains("Unsupported Items"))
        XCTAssertTrue(inspectOutput.contains("finder.legacy-setting = absent [unsupported, universal]"))
        XCTAssertTrue(inspectOutput.contains("Warnings"))
        XCTAssertTrue(inspectOutput.contains("terminal.config-redacted.zshrc:"))
        XCTAssertTrue(inspectOutput.contains("No system settings were changed."))
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
        XCTAssertTrue(output.contains("Sections: 2"))
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
                        SnapshotItem(key: "architecture", value: .string("arm64")),
                        SnapshotItem(
                            key: "username",
                            value: .string("cmb"),
                            classification: .userMustReview,
                            applicability: .userSpecific
                        ),
                        SnapshotItem(
                            key: "hostname",
                            value: .string("reference-mac"),
                            classification: .machineSpecific
                        )
                    ]
                ),
                SnapshotSection(
                    identifier: "terminal",
                    displayName: "Terminal",
                    capturedAt: Date(timeIntervalSince1970: 1_786_492_800),
                    items: [
                        SnapshotItem(
                            key: "icloud.auth-state",
                            value: .string("excluded"),
                            classification: .excluded,
                            applicability: .userSpecific
                        ),
                        SnapshotItem(
                            key: "finder.legacy-setting",
                            value: .absent,
                            classification: .unsupported
                        ),
                        SnapshotItem(
                            key: "terminal.config.zshrc",
                            value: .object(["status": "redacted", "reason": "secret-like values"]),
                            classification: .potentiallySensitive,
                            applicability: .userSpecific
                        )
                    ],
                    warnings: [
                        SnapshotWarning(
                            code: "terminal.config-redacted.zshrc",
                            message: "Shell configuration contains secret-like values and was redacted."
                        )
                    ]
                )
            ]
        )
    }
}
