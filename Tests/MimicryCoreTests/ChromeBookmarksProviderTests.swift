import MimicryCore
import XCTest

final class ChromeBookmarksProviderTests: XCTestCase {
    func testSnapshotCapturesChromeBookmarkMetadataAcrossProfilesAndRedactsURLs() async throws {
        let chromeRootURL = try makeChromeRootURL()
        let defaultProfileURL = chromeRootURL.appendingPathComponent("Default", isDirectory: true)
        let workProfileURL = chromeRootURL.appendingPathComponent("Profile 1", isDirectory: true)
        let defaultBookmarksURL = defaultProfileURL.appendingPathComponent("Bookmarks")
        let workBookmarksURL = workProfileURL.appendingPathComponent("Bookmarks")
        let defaultData = try JSONSerialization.data(withJSONObject: chromeBookmarksJSON(name: "Example", url: "https://example.com/docs?token=secret#private"))
        let workData = try JSONSerialization.data(withJSONObject: chromeBookmarksJSON(name: "OpenAI", url: "https://openai.com"))
        let provider = ChromeBookmarksProvider(
            chromeRootURL: chromeRootURL,
            fileExists: { url in
                [chromeRootURL, defaultBookmarksURL, workBookmarksURL].contains(url)
            },
            directoryContents: { _ in [workProfileURL, defaultProfileURL] },
            dataProvider: { url in
                switch url {
                case defaultBookmarksURL:
                    return defaultData
                case workBookmarksURL:
                    return workData
                default:
                    return Data()
                }
            }
        )

        let section = try await provider.snapshot(context: SnapshotContext(commandRunner: FakeCommandRunner()))

        XCTAssertEqual(section.identifier, "chrome")
        XCTAssertEqual(section.displayName, "Chrome")
        XCTAssertEqual(section.warnings.map(\.code), ["chrome.bookmark-urls-redacted"])
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "chrome.bookmarks.source",
                value: .object([
                    "path": chromeRootURL.path,
                    "status": "captured",
                    "profileCount": "2",
                    "readableProfileCount": "2",
                    "unreadableProfileCount": "0",
                    "folderCount": "6",
                    "bookmarkCount": "2",
                    "redactedURLCount": "1"
                ]),
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "chrome.profile.0001.source",
                value: .object([
                    "profileDirectory": "Default",
                    "bookmarkFile": "Default/Bookmarks",
                    "status": "captured",
                    "folderCount": "3",
                    "bookmarkCount": "1",
                    "redactedURLCount": "1"
                ]),
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "chrome.profile.0001.folder.0001",
                value: .object([
                    "type": "folder",
                    "title": "Bookmarks Bar",
                    "path": "Bookmarks Bar",
                    "childCount": "1"
                ]),
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "chrome.profile.0001.bookmark.0001",
                value: .object([
                    "type": "bookmark",
                    "title": "Example",
                    "folderPath": "Bookmarks Bar",
                    "url": "https://example.com/docs",
                    "urlRedaction": "query,fragment"
                ]),
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "chrome.profile.0002.bookmark.0001",
                value: .object([
                    "type": "bookmark",
                    "title": "OpenAI",
                    "folderPath": "Bookmarks Bar",
                    "url": "https://openai.com",
                    "urlRedaction": "none"
                ]),
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ))
    }

    func testSnapshotReportsMissingChromeProfilesWithoutThrowing() async throws {
        let chromeRootURL = try makeChromeRootURL()
        let provider = ChromeBookmarksProvider(
            chromeRootURL: chromeRootURL,
            fileExists: { _ in false }
        )

        let section = try await provider.snapshot(context: SnapshotContext(commandRunner: FakeCommandRunner()))

        XCTAssertEqual(section.warnings.map(\.code), ["chrome.bookmarks-unavailable"])
        XCTAssertEqual(
            section.items,
            [
                SnapshotItem(
                    key: "chrome.bookmarks.source",
                    value: .object([
                        "path": chromeRootURL.path,
                        "status": "absent",
                        "profileCount": "0",
                        "readableProfileCount": "0",
                        "unreadableProfileCount": "0",
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

    func testSnapshotReportsUnreadableProfileWithoutCapturingBookmarkData() async throws {
        let chromeRootURL = try makeChromeRootURL()
        let profileURL = chromeRootURL.appendingPathComponent("Default", isDirectory: true)
        let bookmarksURL = profileURL.appendingPathComponent("Bookmarks")
        let provider = ChromeBookmarksProvider(
            chromeRootURL: chromeRootURL,
            fileExists: { url in [chromeRootURL, bookmarksURL].contains(url) },
            directoryContents: { _ in [profileURL] },
            dataProvider: { _ in Data("not json".utf8) }
        )

        let section = try await provider.snapshot(context: SnapshotContext(commandRunner: FakeCommandRunner()))

        XCTAssertEqual(section.warnings.map(\.code), ["chrome.bookmarks-unreadable.0001"])
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "chrome.profile.0001.source",
                value: .object([
                    "profileDirectory": "Default",
                    "bookmarkFile": "Default/Bookmarks",
                    "status": "unreadable",
                    "folderCount": "0",
                    "bookmarkCount": "0",
                    "redactedURLCount": "0"
                ]),
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ))
    }

    func testDetectAndLifecycleMethodsDeferApplyToLaterPhase() async throws {
        let chromeRootURL = try makeChromeRootURL()
        let profileURL = chromeRootURL.appendingPathComponent("Default", isDirectory: true)
        let bookmarksURL = profileURL.appendingPathComponent("Bookmarks")
        let provider = ChromeBookmarksProvider(
            chromeRootURL: chromeRootURL,
            fileExists: { url in [chromeRootURL, bookmarksURL].contains(url) },
            directoryContents: { _ in [profileURL] }
        )
        let detection = try await provider.detect(context: DetectionContext(commandRunner: FakeCommandRunner()))
        let valid = try await provider.validate(
            section: SnapshotSection(identifier: "chrome", displayName: "Chrome"),
            context: ValidationContext()
        )
        let invalid = try await provider.validate(
            section: SnapshotSection(identifier: "other", displayName: "Other"),
            context: ValidationContext()
        )
        let actions = try await provider.planApply(
            section: SnapshotSection(identifier: "chrome", displayName: "Chrome"),
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

    private func makeChromeRootURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func chromeBookmarksJSON(name: String, url: String) -> [String: Any] {
        [
            "roots": [
                "bookmark_bar": [
                    "type": "folder",
                    "name": "Bookmarks Bar",
                    "children": [
                        [
                            "type": "url",
                            "name": name,
                            "url": url
                        ]
                    ]
                ],
                "other": [
                    "type": "folder",
                    "name": "Other Bookmarks",
                    "children": []
                ],
                "synced": [
                    "type": "folder",
                    "name": "Mobile Bookmarks",
                    "children": []
                ]
            ]
        ]
    }
}
