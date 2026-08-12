import MimicryCore
import XCTest

final class EnvironmentSnapshotProviderTests: XCTestCase {
    func testSnapshotCapturesCapabilityMetadata() async throws {
        let section = try await EnvironmentSnapshotProvider().snapshot(
            context: SnapshotContext(
                commandRunner: FakeCommandRunner(),
                capabilities: MacCapabilities.environmentProviderFixture(managementState: .managed)
            )
        )

        XCTAssertEqual(section.identifier, "environment")
        XCTAssertEqual(section.warnings, [])
        XCTAssertTrue(section.items.contains(SnapshotItem(key: "macos.version", value: .string("Version 26.0"))))
        XCTAssertTrue(section.items.contains(SnapshotItem(key: "architecture", value: .string("arm64"))))
        XCTAssertTrue(section.items.contains(SnapshotItem(key: "hardware.model", value: .string("MacBookPro18,3"), classification: .hardwareSpecific)))
        XCTAssertTrue(section.items.contains(SnapshotItem(key: "hostname", value: .string("reference-mac.local"), classification: .machineSpecific)))
        XCTAssertTrue(section.items.contains(SnapshotItem(key: "username", value: .string("cmb"), classification: .userMustReview, applicability: .userSpecific)))
        XCTAssertTrue(section.items.contains(SnapshotItem(key: "management", value: .string("managed"), classification: .managed)))
    }

    func testSnapshotWarnsWhenCapabilitiesAreMissing() async throws {
        let section = try await EnvironmentSnapshotProvider().snapshot(
            context: SnapshotContext(commandRunner: FakeCommandRunner())
        )

        XCTAssertEqual(section.items, [])
        XCTAssertEqual(section.warnings.map(\.code), ["environment.capabilities-missing"])
    }

    func testProviderLifecycleMethodsAreInformational() async throws {
        let provider = EnvironmentSnapshotProvider()
        let detection = try await provider.detect(context: DetectionContext(commandRunner: FakeCommandRunner()))
        let valid = try await provider.validate(
            section: SnapshotSection(identifier: "environment", displayName: "Environment"),
            context: ValidationContext()
        )
        let invalid = try await provider.validate(
            section: SnapshotSection(identifier: "other", displayName: "Other"),
            context: ValidationContext()
        )
        let actions = try await provider.planApply(
            section: SnapshotSection(identifier: "environment", displayName: "Environment"),
            context: ApplyContext(commandRunner: FakeCommandRunner())
        )
        let result = try await provider.apply(
            action: actions[0],
            context: ApplyContext(commandRunner: FakeCommandRunner())
        )

        XCTAssertEqual(detection.status, .success)
        XCTAssertEqual(valid.status, .success)
        XCTAssertEqual(invalid.status, .warning)
        XCTAssertEqual(actions.map(\.kind), [.skip])
        XCTAssertEqual(result.status, .skipped)
    }
}

private extension MacCapabilities {
    static func environmentProviderFixture(managementState: CapabilityState) -> MacCapabilities {
        MacCapabilities(
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
                hasMAS: true
            ),
            services: MacServiceCapabilities(
                iCloudState: .available,
                appStoreState: .available,
                managementState: managementState
            )
        )
    }
}
