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
            macOSVersion: "26.0",
            architecture: .arm64,
            hardwareModel: "MacBookPro",
            hostname: "reference-mac",
            username: "cmb"
        )

        XCTAssertEqual(capabilities.fileVaultState, .unknown)
        XCTAssertEqual(capabilities.sipState, .unknown)
        XCTAssertEqual(capabilities.iCloudState, .unknown)
        XCTAssertEqual(capabilities.appStoreState, .unknown)
        XCTAssertEqual(capabilities.managementState, .unknown)
        XCTAssertFalse(capabilities.homebrew.isInstalled)
    }
}
