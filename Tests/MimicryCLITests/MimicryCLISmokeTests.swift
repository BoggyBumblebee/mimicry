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

    func testDiffRendersComparisonAgainstCurrentSnapshot() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let packageURL = temporaryDirectory.appendingPathComponent("fixture.mimicry")
        let snapshot = MimicrySnapshot.phaseOneCLIFixture()
        _ = try MimicryPackageStore().write(snapshot: snapshot, to: packageURL)

        let currentSnapshot = MimicrySnapshot.currentDiffFixture()
        let output = try MimicryCLIResponses.diff(
            packagePath: packageURL.path,
            currentSnapshot: currentSnapshot
        )

        XCTAssertTrue(output.contains("Mimicry Snapshot Diff"))
        XCTAssertTrue(output.contains("Snapshot: \(packageURL.path)"))
        XCTAssertTrue(output.contains("Reference: reference-mac (cmb)"))
        XCTAssertTrue(output.contains("Current: current-mac (cmb)"))
        XCTAssertTrue(output.contains("- matching: 2"))
        XCTAssertTrue(output.contains("- changed: 1"))
        XCTAssertTrue(output.contains("- missing: 1"))
        XCTAssertTrue(output.contains("- current only: 1"))
        XCTAssertTrue(output.contains("- skipped: 1"))
        XCTAssertTrue(output.contains("- unsupported: 1"))
        XCTAssertTrue(output.contains("Changed Items"))
        XCTAssertTrue(output.contains("hostname: reference-mac -> current-mac"))
        XCTAssertTrue(output.contains("Current-Only Items"))
        XCTAssertTrue(output.contains("current-only: current has true; not in snapshot"))
        XCTAssertTrue(output.contains("Skipped Items"))
        XCTAssertTrue(output.contains("icloud.auth-state"))
        XCTAssertTrue(output.contains("Snapshot Warnings"))
        XCTAssertTrue(output.contains("Current Warnings"))
        XCTAssertTrue(output.contains("No system settings were changed."))
    }

    func testApplyDryRunRendersActionPlanWithoutMutatingSystemState() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let packageURL = temporaryDirectory.appendingPathComponent("fixture.mimicry")
        let snapshot = MimicrySnapshot.phaseOneCLIFixture()
        _ = try MimicryPackageStore().write(snapshot: snapshot, to: packageURL)

        let output = try MimicryCLIResponses.apply(
            packagePath: packageURL.path,
            dryRun: true,
            currentSnapshot: .currentDiffFixture()
        )

        XCTAssertTrue(output.contains("Mimicry Apply Dry Run"))
        XCTAssertTrue(output.contains("Snapshot: \(packageURL.path)"))
        XCTAssertTrue(output.contains("Actions: 5"))
        XCTAssertTrue(output.contains("- install: 0"))
        XCTAssertTrue(output.contains("- configure: 0"))
        XCTAssertTrue(output.contains("- skip: 2"))
        XCTAssertTrue(output.contains("- blocked: 1"))
        XCTAssertTrue(output.contains("- requires user action: 2"))
        XCTAssertTrue(output.contains("SKIP"))
        XCTAssertTrue(output.contains("icloud.auth-state is excluded"))
        XCTAssertTrue(output.contains("BLOCKED"))
        XCTAssertTrue(output.contains("finder.legacy-setting is marked unsupported"))
        XCTAssertTrue(output.contains("REQUIRES USER ACTION"))
        XCTAssertTrue(output.contains("hostname: would change"))
        XCTAssertTrue(output.contains("username: would add"))
        XCTAssertTrue(output.contains("No system settings were changed."))
    }

    func testApplyWithoutDryRunRefusesToMutateSystemState() throws {
        let output = try MimicryCLIResponses.apply(packagePath: "target.mimicry", dryRun: false)

        XCTAssertTrue(output.contains("Apply is not implemented yet"))
        XCTAssertTrue(output.contains("Use --dry-run"))
        XCTAssertTrue(output.contains("No system settings were changed."))
    }

    func testConfirmedApplyRendersFinderApplySummary() {
        let output = MimicryCLIResponses.confirmedApply(
            packagePath: "target.mimicry",
            summary: FinderPreferenceApplySummary(
                backupURL: URL(fileURLWithPath: "finder-backup.json"),
                results: [
                    ApplyResult(
                        actionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                        status: .success,
                        message: "Applied Finder preference ShowPathbar."
                    )
                ]
            )
        )

        XCTAssertTrue(output.contains("Mimicry Apply"))
        XCTAssertTrue(output.contains("Mode: confirmed Finder-safe apply"))
        XCTAssertTrue(output.contains("Backup:"))
        XCTAssertTrue(output.contains("Applied: 1"))
        XCTAssertTrue(output.contains("Warnings: 0"))
        XCTAssertTrue(output.contains("- success: Applied Finder preference ShowPathbar."))
        XCTAssertTrue(output.contains("Only explicitly classified safe Finder preferences were considered."))
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

    static func currentDiffFixture() -> MimicrySnapshot {
        MimicrySnapshot(
            mimicryVersion: "0.1.0",
            createdAt: Date(timeIntervalSince1970: 1_786_492_800),
            source: SnapshotSource(
                macOSVersion: "26.0",
                architecture: "arm64",
                hardwareModel: "MacBookPro",
                hostname: "current-mac",
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
                            key: "hostname",
                            value: .string("current-mac"),
                            classification: .machineSpecific
                        ),
                        SnapshotItem(key: "current-only", value: .bool(true))
                    ],
                    warnings: [
                        SnapshotWarning(code: "current-warning", message: "Current warning")
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
                        SnapshotWarning(code: "current-terminal-warning", message: "Current terminal warning")
                    ]
                )
            ]
        )
    }
}
