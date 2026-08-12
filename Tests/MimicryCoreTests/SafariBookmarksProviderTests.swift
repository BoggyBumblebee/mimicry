import MimicryCore
import XCTest

final class SafariBookmarksProviderTests: XCTestCase {
    func testSnapshotCapturesSafariBookmarkMetadataAndRedactsURLDetails() async throws {
        let bookmarksURL = try makeBookmarksURL()
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: safariBookmarksPlist(),
            format: .xml,
            options: 0
        )
        let provider = SafariBookmarksProvider(
            bookmarksURL: bookmarksURL,
            fileExists: { _ in true },
            dataProvider: { _ in plistData }
        )

        let section = try await provider.snapshot(context: SnapshotContext(commandRunner: FakeCommandRunner()))

        XCTAssertEqual(section.identifier, "safari")
        XCTAssertEqual(section.displayName, "Safari")
        XCTAssertEqual(section.warnings.map(\.code), ["safari.bookmark-urls-redacted"])
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "safari.bookmarks.source",
                value: .object([
                    "path": "~/Library/Safari/Bookmarks.plist",
                    "status": "captured",
                    "folderCount": "2",
                    "bookmarkCount": "2",
                    "redactedURLCount": "1"
                ]),
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "safari.folder.0001",
                value: .object([
                    "type": "folder",
                    "title": "Favorites",
                    "path": "Favorites",
                    "childCount": "2"
                ]),
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "safari.bookmark.0001",
                value: .object([
                    "type": "bookmark",
                    "title": "Example",
                    "folderPath": "Favorites",
                    "url": "https://example.com/docs",
                    "urlRedaction": "query,fragment"
                ]),
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "safari.bookmark.0002",
                value: .object([
                    "type": "bookmark",
                    "title": "OpenAI",
                    "folderPath": "Favorites/Work",
                    "url": "https://openai.com",
                    "urlRedaction": "none"
                ]),
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ))
    }

    func testSnapshotReportsMissingSafariBookmarksWithoutThrowing() async throws {
        let provider = SafariBookmarksProvider(
            bookmarksURL: try makeBookmarksURL(),
            fileExists: { _ in false }
        )

        let section = try await provider.snapshot(context: SnapshotContext(commandRunner: FakeCommandRunner()))

        XCTAssertEqual(section.warnings.map(\.code), ["safari.bookmarks-unavailable"])
        XCTAssertEqual(
            section.items,
            [
                SnapshotItem(
                    key: "safari.bookmarks.source",
                    value: .object([
                        "path": "~/Library/Safari/Bookmarks.plist",
                        "status": "absent",
                        "folderCount": "0",
                        "bookmarkCount": "0",
                        "redactedURLCount": "0"
                    ]),
                    classification: .userMustReview,
                    applicability: .userSpecific
                )
            ]
        )
    }

    func testSnapshotReportsUnreadableSafariBookmarksWithoutCapturingData() async throws {
        let provider = SafariBookmarksProvider(
            bookmarksURL: try makeBookmarksURL(),
            fileExists: { _ in true },
            dataProvider: { _ in Data("not a plist".utf8) }
        )

        let section = try await provider.snapshot(context: SnapshotContext(commandRunner: FakeCommandRunner()))

        XCTAssertEqual(section.warnings.map(\.code), ["safari.bookmarks-unreadable"])
        XCTAssertEqual(section.items.first?.key, "safari.bookmarks.source")
        XCTAssertEqual(section.items.first?.classification, .userMustReview)
        XCTAssertEqual(section.items.first?.applicability, .userSpecific)
        XCTAssertTrue(String(describing: section.items).contains("unreadable"))
    }

    func testDetectAndLifecycleMethodsDeferApplyToLaterPhase() async throws {
        let provider = SafariBookmarksProvider(
            bookmarksURL: try makeBookmarksURL(),
            fileExists: { _ in true }
        )
        let detection = try await provider.detect(context: DetectionContext(commandRunner: FakeCommandRunner()))
        let valid = try await provider.validate(
            section: SnapshotSection(identifier: "safari", displayName: "Safari"),
            context: ValidationContext()
        )
        let invalid = try await provider.validate(
            section: SnapshotSection(identifier: "other", displayName: "Other"),
            context: ValidationContext()
        )
        let actions = try await provider.planApply(
            section: SnapshotSection(identifier: "safari", displayName: "Safari"),
            context: ApplyContext(commandRunner: FakeCommandRunner())
        )
        let result = try await provider.apply(
            action: actions[0],
            context: ApplyContext(commandRunner: FakeCommandRunner())
        )

        XCTAssertEqual(detection.status, .success)
        XCTAssertEqual(valid.status, .success)
        XCTAssertEqual(invalid.status, .warning)
        XCTAssertEqual(actions.map(\.kind), [.requiresUserAction])
        XCTAssertEqual(result.status, .skipped)
    }

    private func makeBookmarksURL() throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        return temporaryDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Safari", isDirectory: true)
            .appendingPathComponent("Bookmarks.plist")
    }

    private func safariBookmarksPlist() -> [String: Any] {
        [
            "Children": [
                [
                    "WebBookmarkType": "WebBookmarkTypeList",
                    "Title": "Favorites",
                    "Children": [
                        [
                            "WebBookmarkType": "WebBookmarkTypeLeaf",
                            "URIDictionary": ["title": "Example"],
                            "URLString": "https://example.com/docs?token=secret#private"
                        ],
                        [
                            "WebBookmarkType": "WebBookmarkTypeList",
                            "Title": "Work",
                            "Children": [
                                [
                                    "WebBookmarkType": "WebBookmarkTypeLeaf",
                                    "URIDictionary": ["title": "OpenAI"],
                                    "URLString": "https://openai.com"
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
    }
}
