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

    func testPlanSummarizesBrowserBookmarkImportPreviewWithoutDuplicatingExistingBookmarks() {
        let reference = MimicrySnapshot.applyFixture(
            sections: [
                SnapshotSection(
                    identifier: "firefox",
                    displayName: "Firefox",
                    items: [
                        browserSourceItem(identifier: "firefox", status: "captured"),
                        browserBookmarkItem(
                            key: "firefox.profile.0001.bookmark.0001",
                            title: "Example",
                            folderPath: "Bookmarks Menu",
                            url: "https://example.com/docs"
                        ),
                        browserBookmarkItem(
                            key: "firefox.profile.0001.bookmark.0002",
                            title: "OpenAI",
                            folderPath: "Bookmarks Menu/Work",
                            url: "https://openai.com"
                        ),
                        browserBookmarkItem(
                            key: "firefox.profile.0001.bookmark.0003",
                            title: "OpenAI",
                            folderPath: "Bookmarks Menu/Work",
                            url: "https://openai.com"
                        )
                    ]
                )
            ]
        )
        let current = MimicrySnapshot.applyFixture(
            sections: [
                SnapshotSection(
                    identifier: "firefox",
                    displayName: "Firefox",
                    items: [
                        browserSourceItem(identifier: "firefox", status: "captured"),
                        browserBookmarkItem(
                            key: "firefox.profile.0002.bookmark.0099",
                            title: "OpenAI",
                            folderPath: "Bookmarks Menu/Work",
                            url: "https://openai.com"
                        )
                    ]
                )
            ]
        )

        let plan = SnapshotApplyPlanner().plan(reference: reference, current: current)

        XCTAssertEqual(plan.count(.requiresUserAction), 1)
        XCTAssertEqual(plan.actions.first?.providerIdentifier, "firefox")
        XCTAssertEqual(plan.actions.first?.kind, .requiresUserAction)
        XCTAssertEqual(
            plan.actions.first?.summary,
            "Firefox bookmark import preview: 1 importable, 1 already present, 1 skipped, 0 blocked; import is not implemented yet and requires user review."
        )
    }

    func testPlanSummarizesUnavailableBrowserSources() {
        let reference = MimicrySnapshot.applyFixture(
            sections: [
                SnapshotSection(
                    identifier: "safari",
                    displayName: "Safari",
                    items: [
                        browserSourceItem(identifier: "safari", status: "unreadable")
                    ]
                ),
                SnapshotSection(
                    identifier: "chrome",
                    displayName: "Chrome",
                    items: [
                        browserSourceItem(identifier: "chrome", status: "absent")
                    ]
                )
            ]
        )
        let current = MimicrySnapshot.applyFixture(sections: [])

        let plan = SnapshotApplyPlanner().plan(reference: reference, current: current)

        XCTAssertEqual(plan.count(.requiresUserAction), 2)
        XCTAssertTrue(plan.actions.contains {
            $0.providerIdentifier == "safari"
                && $0.summary.contains("0 importable, 0 already present, 0 skipped, 1 blocked")
        })
        XCTAssertTrue(plan.actions.contains {
            $0.providerIdentifier == "chrome"
                && $0.summary.contains("0 importable, 0 already present, 1 skipped, 0 blocked")
        })
    }

    func testPlanSkipsCapturedBrowserSectionWithNoBookmarks() {
        let reference = MimicrySnapshot.applyFixture(
            sections: [
                SnapshotSection(
                    identifier: "safari",
                    displayName: "Safari",
                    items: [
                        browserSourceItem(identifier: "safari", status: "captured")
                    ]
                )
            ]
        )
        let current = MimicrySnapshot.applyFixture(sections: [])

        let plan = SnapshotApplyPlanner().plan(reference: reference, current: current)

        XCTAssertTrue(plan.actions.isEmpty)
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

private func browserSourceItem(identifier: String, status: String) -> SnapshotItem {
    SnapshotItem(
        key: "\(identifier).bookmarks.source",
        value: .object([
            "status": status,
            "bookmarkCount": "0",
            "folderCount": "0",
            "redactedURLCount": "0"
        ]),
        classification: .userMustReview,
        applicability: .userSpecific
    )
}

private func browserBookmarkItem(
    key: String,
    title: String,
    folderPath: String,
    url: String
) -> SnapshotItem {
    SnapshotItem(
        key: key,
        value: .object([
            "type": "bookmark",
            "title": title,
            "folderPath": folderPath,
            "url": url,
            "urlRedaction": "none"
        ]),
        classification: .userMustReview,
        applicability: .userSpecific
    )
}
