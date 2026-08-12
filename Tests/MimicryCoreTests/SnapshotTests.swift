import MimicryCore
import XCTest

final class SnapshotTests: XCTestCase {
    func testSnapshotRoundTripsThroughJSON() throws {
        let snapshot = MimicrySnapshot.phaseOneFixture()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MimicrySnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
    }

    func testSnapshotItemKeepsSafetyClassification() {
        let item = SnapshotItem(
            key: "shell.profile",
            value: .string("redacted"),
            classification: .userMustReview,
            applicability: .userSpecific
        )

        XCTAssertEqual(item.classification, .userMustReview)
        XCTAssertEqual(item.applicability, .userSpecific)
    }

    func testSnapshotIdentifiableIDsUseStableKeys() {
        let section = SnapshotSection(identifier: "environment", displayName: "Environment")
        let item = SnapshotItem(key: "architecture", value: .string("arm64"))
        let warning = SnapshotWarning(code: "redacted", message: "Sensitive value redacted.")

        XCTAssertEqual(section.id, "environment")
        XCTAssertEqual(item.id, "architecture")
        XCTAssertEqual(warning.id, "redacted")
        XCTAssertEqual(warning.message, "Sensitive value redacted.")
    }
}

extension MimicrySnapshot {
    static func phaseOneFixture() -> MimicrySnapshot {
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
