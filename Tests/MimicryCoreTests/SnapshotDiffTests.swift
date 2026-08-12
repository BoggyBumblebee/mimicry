import MimicryCore
import XCTest

final class SnapshotDiffTests: XCTestCase {
    func testDiffClassifiesMatchingChangedMissingCurrentOnlySkippedAndUnsupportedItems() {
        let report = SnapshotDiffEngine().diff(
            reference: .diffFixture(
                sections: [
                    SnapshotSection(
                        identifier: "finder",
                        displayName: "Finder",
                        items: [
                            SnapshotItem(key: "matching", value: .bool(true)),
                            SnapshotItem(key: "changed", value: .string("old")),
                            SnapshotItem(key: "missing", value: .int(1)),
                            SnapshotItem(key: "excluded", value: .string("secret"), classification: .excluded),
                            SnapshotItem(key: "unsupported", value: .absent, classification: .unsupported)
                        ],
                        warnings: [
                            SnapshotWarning(code: "snapshot-warning", message: "Snapshot warning")
                        ]
                    )
                ]
            ),
            current: .diffFixture(
                sections: [
                    SnapshotSection(
                        identifier: "finder",
                        displayName: "Finder",
                        items: [
                            SnapshotItem(key: "matching", value: .bool(true)),
                            SnapshotItem(key: "changed", value: .string("new")),
                            SnapshotItem(key: "current-only", value: .string("current"))
                        ],
                        warnings: [
                            SnapshotWarning(code: "current-warning", message: "Current warning")
                        ]
                    )
                ]
            )
        )

        XCTAssertEqual(report.itemCount, 6)
        XCTAssertEqual(report.count(.matching), 1)
        XCTAssertEqual(report.count(.changed), 1)
        XCTAssertEqual(report.count(.missing), 1)
        XCTAssertEqual(report.count(.currentOnly), 1)
        XCTAssertEqual(report.count(.skipped), 1)
        XCTAssertEqual(report.count(.unsupported), 1)
        XCTAssertEqual(report.sections.first?.referenceWarnings.first?.code, "snapshot-warning")
        XCTAssertEqual(report.sections.first?.currentWarnings.first?.code, "current-warning")
    }

    func testDiffReportsMissingAndCurrentOnlySections() {
        let report = SnapshotDiffEngine().diff(
            reference: .diffFixture(
                sections: [
                    SnapshotSection(
                        identifier: "reference-only",
                        displayName: "Reference Only",
                        items: [
                            SnapshotItem(key: "reference.item", value: .bool(true))
                        ]
                    )
                ]
            ),
            current: .diffFixture(
                sections: [
                    SnapshotSection(
                        identifier: "current-only",
                        displayName: "Current Only",
                        items: [
                            SnapshotItem(key: "current.item", value: .bool(true))
                        ]
                    )
                ]
            )
        )

        XCTAssertEqual(report.sections.map(\.identifier), ["current-only", "reference-only"])
        XCTAssertEqual(report.count(.missing), 1)
        XCTAssertEqual(report.count(.currentOnly), 1)
    }
}

private extension MimicrySnapshot {
    static func diffFixture(sections: [SnapshotSection]) -> MimicrySnapshot {
        MimicrySnapshot(
            mimicryVersion: "0.1.0",
            source: SnapshotSource(
                macOSVersion: "26.0",
                architecture: "arm64",
                hardwareModel: "MacBookPro",
                hostname: "reference-mac",
                username: "cmb"
            ),
            sections: sections
        )
    }
}
