import MimicryCore
import XCTest

final class MacCapabilitiesTests: XCTestCase {
    func testAppleSiliconArchitectureFlag() {
        XCTAssertTrue(MacArchitecture.arm64.isAppleSilicon)
        XCTAssertFalse(MacArchitecture.x86_64.isAppleSilicon)
        XCTAssertFalse(MacArchitecture.unknown.isAppleSilicon)
    }

    func testCapabilitiesDefaultUnknownStates() {
        let capabilities = MacCapabilities(
            environment: MacEnvironment(
                macOSVersion: "26.0",
                architecture: .arm64,
                hardwareModel: "MacBookPro",
                hostname: "reference-mac",
                username: "cmb"
            )
        )

        XCTAssertEqual(capabilities.fileVaultState, .unknown)
        XCTAssertEqual(capabilities.sipState, .unknown)
        XCTAssertEqual(capabilities.iCloudState, .unknown)
        XCTAssertEqual(capabilities.appStoreState, .unknown)
        XCTAssertEqual(capabilities.managementState, .unknown)
        XCTAssertFalse(capabilities.homebrew.isInstalled)
    }

    func testCapabilityPathsAreCustomizable() async {
        let customPaths = MacCapabilityPaths(
            developerTools: MacCapabilityDeveloperToolPaths(
                xcodeSelect: URL(fileURLWithPath: "/custom/xcode-select"),
                xcodebuild: URL(fileURLWithPath: "/custom/xcodebuild")
            ),
            shellTools: MacCapabilityShellToolPaths(
                id: URL(fileURLWithPath: "/custom/id"),
                which: URL(fileURLWithPath: "/custom/which"),
                env: URL(fileURLWithPath: "/custom/env")
            ),
            securityTools: MacCapabilitySecurityToolPaths(
                csrutil: URL(fileURLWithPath: "/custom/csrutil"),
                fdesetup: URL(fileURLWithPath: "/custom/fdesetup"),
                profiles: URL(fileURLWithPath: "/custom/profiles")
            ),
            homebrewPrefixes: MacCapabilityHomebrewPrefixes(
                appleSilicon: URL(fileURLWithPath: "/custom/homebrew"),
                intel: URL(fileURLWithPath: "/custom/local")
            )
        )
        let runner = FakeCommandRunner(results: [
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "staff everyone admin\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "developer tools\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "Xcode 26.0\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "brew\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "/custom/homebrew\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "Homebrew 5.0.0\n"),
            CommandResult(executable: "", arguments: [], exitCode: 1),
            CommandResult(executable: "", arguments: [], exitCode: 1),
            CommandResult(executable: "", arguments: [], exitCode: 1),
            CommandResult(executable: "", arguments: [], exitCode: 1)
        ])
        let detector = MacCapabilitiesDetector(
            runner: runner,
            paths: customPaths,
            systemInfoProvider: {
                MacCapabilitySystemInfo.testFixture()
            }
        )

        let capabilities = await detector.detect()
        let invocations = await runner.invocations

        XCTAssertEqual(invocations.map(\.executable), [
            "/custom/id",
            "/custom/xcode-select",
            "/custom/xcodebuild",
            "/custom/which",
            "/custom/env",
            "/custom/env",
            "/custom/which",
            "/custom/csrutil",
            "/custom/fdesetup",
            "/custom/profiles"
        ])
        XCTAssertEqual(capabilities.homebrew.architecture, .arm64)
    }

    func testDetectorBuildsCapabilitiesFromSuccessfulCommandProbes() async {
        let runner = FakeCommandRunner(results: [
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "staff everyone admin\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "/Applications/Xcode.app/Contents/Developer\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "Xcode 26.0\nBuild version 17A1\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "/opt/homebrew/bin/brew\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "/opt/homebrew\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "Homebrew 5.0.0\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "/opt/homebrew/bin/mas\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "System Integrity Protection status: enabled.\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "FileVault is On.\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "Enrolled via DEP: No\nMDM enrollment: No\n")
        ])
        let detector = MacCapabilitiesDetector(
            runner: runner,
            systemInfoProvider: {
                MacCapabilitySystemInfo.testFixture(
                    iCloudDocumentsDirectoryExists: true,
                    appStoreApplicationExists: true
                )
            }
        )

        let capabilities = await detector.detect()

        XCTAssertTrue(capabilities.hasAdministratorPrivileges)
        XCTAssertTrue(capabilities.hasCommandLineTools)
        XCTAssertEqual(capabilities.xcodeVersion, "Xcode 26.0")
        XCTAssertEqual(
            capabilities.homebrew,
            HomebrewCapability(
                isInstalled: true,
                prefix: "/opt/homebrew",
                version: "Homebrew 5.0.0",
                architecture: .arm64
            )
        )
        XCTAssertTrue(capabilities.hasMAS)
        XCTAssertEqual(capabilities.sipState, .enabled)
        XCTAssertEqual(capabilities.fileVaultState, .enabled)
        XCTAssertEqual(capabilities.iCloudState, .available)
        XCTAssertEqual(capabilities.appStoreState, .available)
        XCTAssertEqual(capabilities.managementState, .unavailable)
    }

    func testDetectorReportsMissingHomebrewAndMasAsWarningsInputs() async {
        let runner = FakeCommandRunner(results: [
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "staff everyone\n"),
            CommandResult(executable: "", arguments: [], exitCode: 1, standardError: "xcode-select: error\n"),
            CommandResult(executable: "", arguments: [], exitCode: 1, standardError: "xcodebuild: error\n"),
            CommandResult(executable: "", arguments: [], exitCode: 1, standardError: "brew not found\n"),
            CommandResult(executable: "", arguments: [], exitCode: 1, standardError: "mas not found\n"),
            CommandResult(executable: "", arguments: [], exitCode: 1, standardError: "csrutil unavailable\n"),
            CommandResult(executable: "", arguments: [], exitCode: 1, standardError: "fdesetup unavailable\n"),
            CommandResult(executable: "", arguments: [], exitCode: 1, standardError: "profiles unavailable\n")
        ])
        let detector = MacCapabilitiesDetector(
            runner: runner,
            systemInfoProvider: {
                MacCapabilitySystemInfo.testFixture(
                    iCloudDocumentsDirectoryExists: false,
                    appStoreApplicationExists: false
                )
            }
        )

        let capabilities = await detector.detect()

        XCTAssertFalse(capabilities.hasAdministratorPrivileges)
        XCTAssertFalse(capabilities.hasCommandLineTools)
        XCTAssertNil(capabilities.xcodeVersion)
        XCTAssertFalse(capabilities.homebrew.isInstalled)
        XCTAssertFalse(capabilities.hasMAS)
        XCTAssertEqual(capabilities.sipState, .unknown)
        XCTAssertEqual(capabilities.fileVaultState, .unknown)
        XCTAssertEqual(capabilities.iCloudState, .requiresUserAction)
        XCTAssertEqual(capabilities.appStoreState, .unknown)
        XCTAssertEqual(capabilities.managementState, .unknown)
    }

    func testDetectorTreatsThrownCommandProbesAsUnknownOrUnavailable() async {
        let detector = MacCapabilitiesDetector(
            runner: ThrowingCommandRunner(),
            systemInfoProvider: {
                MacCapabilitySystemInfo.testFixture()
            }
        )

        let capabilities = await detector.detect()

        XCTAssertFalse(capabilities.hasAdministratorPrivileges)
        XCTAssertFalse(capabilities.hasCommandLineTools)
        XCTAssertNil(capabilities.xcodeVersion)
        XCTAssertFalse(capabilities.homebrew.isInstalled)
        XCTAssertFalse(capabilities.hasMAS)
        XCTAssertEqual(capabilities.sipState, .unknown)
        XCTAssertEqual(capabilities.fileVaultState, .unknown)
        XCTAssertEqual(capabilities.managementState, .unknown)
    }
}

private struct ThrowingCommandRunner: CommandRunner {
    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]?
    ) async throws -> CommandResult {
        throw CocoaError(.executableNotLoadable)
    }
}

private extension MacCapabilitySystemInfo {
    static func testFixture(
        iCloudDocumentsDirectoryExists: Bool = false,
        appStoreApplicationExists: Bool = false
    ) -> MacCapabilitySystemInfo {
        MacCapabilitySystemInfo(
            macOSVersion: "Version 26.0",
            architecture: .arm64,
            hardwareModel: "MacBookPro18,3",
            hostname: "reference-mac.local",
            username: "cmb",
            iCloudDocumentsDirectoryExists: iCloudDocumentsDirectoryExists,
            appStoreApplicationExists: appStoreApplicationExists
        )
    }
}
