import MimicryCore
import XCTest

final class SnapshotApplyPlannerTests: XCTestCase {
    func testPlanMapsDiffItemsToDryRunActionKinds() {
        let reference = MimicrySnapshot.applyFixture(
            sections: [
                SnapshotSection(
                    identifier: "homebrew",
                    displayName: "Homebrew",
                    items: [
                        SnapshotItem(key: "homebrew.formula.git", value: .object(["name": "git", "version": "2.55.0"])),
                        SnapshotItem(key: "homebrew.prefix", value: .string("/opt/homebrew"), classification: .machineSpecific)
                    ]
                ),
                SnapshotSection(
                    identifier: "finder",
                    displayName: "Finder",
                    items: [
                        SnapshotItem(key: "finder.ShowPathbar", value: .bool(true)),
                        SnapshotItem(key: "finder.legacy", value: .absent, classification: .unsupported)
                    ]
                ),
                SnapshotSection(
                    identifier: "icloud",
                    displayName: "iCloud",
                    items: [
                        SnapshotItem(key: "icloud.auth-state", value: .string("excluded"), classification: .excluded)
                    ]
                )
            ]
        )
        let current = MimicrySnapshot.applyFixture(
            sections: [
                SnapshotSection(
                    identifier: "finder",
                    displayName: "Finder",
                    items: [
                        SnapshotItem(key: "finder.ShowPathbar", value: .bool(false)),
                        SnapshotItem(key: "finder.current-only", value: .bool(true))
                    ]
                )
            ]
        )

        let plan = SnapshotApplyPlanner().plan(reference: reference, current: current)

        XCTAssertEqual(plan.count(.install), 1)
        XCTAssertEqual(plan.count(.configure), 1)
        XCTAssertEqual(plan.count(.skip), 2)
        XCTAssertEqual(plan.count(.blocked), 1)
        XCTAssertEqual(plan.count(.requiresUserAction), 1)
        XCTAssertTrue(plan.actions.contains { $0.kind == .install && $0.summary.contains("homebrew.formula.git") })
        XCTAssertTrue(plan.actions.contains { $0.kind == .configure && $0.summary.contains("finder.ShowPathbar") })
        XCTAssertTrue(plan.actions.contains { $0.kind == .requiresUserAction && $0.summary.contains("homebrew.prefix") })
    }
}

private extension MimicrySnapshot {
    static func applyFixture(sections: [SnapshotSection]) -> MimicrySnapshot {
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
