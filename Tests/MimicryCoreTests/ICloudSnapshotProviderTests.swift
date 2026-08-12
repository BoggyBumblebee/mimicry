import MimicryCore
import XCTest

final class ICloudSnapshotProviderTests: XCTestCase {
    func testSnapshotCapturesAvailableICloudMetadataWithoutAuthState() async throws {
        let provider = ICloudSnapshotProvider(
            homeDirectory: URL(fileURLWithPath: "/test-home"),
            fileExists: { _ in true }
        )

        let section = try await provider.snapshot(
            context: SnapshotContext(
                commandRunner: FakeCommandRunner(),
                capabilities: MacCapabilities.iCloudFixture(state: .available)
            )
        )

        XCTAssertEqual(section.identifier, "icloud")
        XCTAssertEqual(section.warnings, [])
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "icloud.state",
                value: .string("available"),
                applicability: .userSpecific
            )
        ))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "icloud.drive-container",
                value: .object([
                    "path": "~/Library/Mobile Documents",
                    "exists": "true",
                    "status": "available"
                ]),
                applicability: .userSpecific
            )
        ))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "icloud.auth-state",
                value: .string("excluded"),
                classification: .excluded,
                applicability: .userSpecific
            )
        ))
    }

    func testSnapshotReportsRequiredUserActionWhenICloudCannotBeConfirmed() async throws {
        let provider = ICloudSnapshotProvider(
            homeDirectory: URL(fileURLWithPath: "/test-home"),
            fileExists: { _ in false }
        )

        let section = try await provider.snapshot(context: SnapshotContext(commandRunner: FakeCommandRunner()))

        XCTAssertEqual(section.warnings.map(\.code), ["icloud.requires-user-action"])
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "icloud.state",
                value: .string("requiresUserAction"),
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "icloud.drive-container",
                value: .object([
                    "path": "~/Library/Mobile Documents",
                    "exists": "false",
                    "status": "requiresUserAction"
                ]),
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ))
    }

    func testDetectReportsLocalMetadataAvailability() async throws {
        let available = try await ICloudSnapshotProvider(fileExists: { _ in true }).detect(
            context: DetectionContext(commandRunner: FakeCommandRunner())
        )
        let unavailable = try await ICloudSnapshotProvider(fileExists: { _ in false }).detect(
            context: DetectionContext(commandRunner: FakeCommandRunner())
        )

        XCTAssertEqual(available.status, .success)
        XCTAssertEqual(unavailable.status, .warning)
    }

    func testProviderLifecycleMethodsRequireUserActionForApply() async throws {
        let provider = ICloudSnapshotProvider()
        let valid = try await provider.validate(
            section: SnapshotSection(identifier: "icloud", displayName: "iCloud"),
            context: ValidationContext()
        )
        let invalid = try await provider.validate(
            section: SnapshotSection(identifier: "other", displayName: "Other"),
            context: ValidationContext()
        )
        let actions = try await provider.planApply(
            section: SnapshotSection(identifier: "icloud", displayName: "iCloud"),
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

private extension MacCapabilities {
    static func iCloudFixture(state: CapabilityState) -> MacCapabilities {
        MacCapabilities(
            environment: MacEnvironment(
                macOSVersion: "Version 26.0",
                architecture: .arm64,
                hardwareModel: "MacBookPro18,3",
                hostname: "reference-mac.local",
                username: "cmb"
            ),
            services: MacServiceCapabilities(iCloudState: state)
        )
    }
}
