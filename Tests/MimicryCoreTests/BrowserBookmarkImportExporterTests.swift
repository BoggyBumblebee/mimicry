import MimicryCore
import XCTest

final class BrowserBookmarkImportExporterTests: XCTestCase {
    func testDocumentExportsSanitizedBrowserBookmarksAsImportableHTML() {
        let snapshot = MimicrySnapshot.browserImportFixture(
            sections: [
                SnapshotSection(
                    identifier: "safari",
                    displayName: "Safari",
                    items: [
                        browserSourceItem(identifier: "safari", status: "captured"),
                        browserBookmarkItem(
                            key: "safari.bookmark.0001",
                            title: "A & B <Docs>",
                            folderPath: "Bookmarks Bar",
                            url: "https://example.com/docs"
                        )
                    ]
                ),
                SnapshotSection(
                    identifier: "chrome",
                    displayName: "Chrome",
                    items: [
                        browserSourceItem(identifier: "chrome", status: "captured"),
                        browserBookmarkItem(
                            key: "chrome.profile.0001.bookmark.0001",
                            title: "OpenAI",
                            folderPath: "Bookmarks Bar/Work",
                            url: "https://openai.com"
                        )
                    ]
                )
            ]
        )

        let document = BrowserBookmarkImportExporter().document(for: snapshot)

        XCTAssertEqual(document.summary.browserSectionCount, 2)
        XCTAssertEqual(document.summary.exportedBookmarkCount, 2)
        XCTAssertEqual(document.summary.skippedDuplicateCount, 0)
        XCTAssertEqual(document.summary.skippedInvalidCount, 0)
        XCTAssertEqual(document.summary.skippedUnavailableSourceCount, 0)
        XCTAssertTrue(document.html.contains("<!DOCTYPE NETSCAPE-Bookmark-file-1>"))
        XCTAssertTrue(document.html.contains("<DT><H3>Chrome</H3>"))
        XCTAssertTrue(document.html.contains("<DT><H3>Safari</H3>"))
        XCTAssertTrue(document.html.contains("<DT><H3>Bookmarks Bar/Work</H3>"))
        XCTAssertTrue(document.html.contains("<A HREF=\"https://example.com/docs\">A &amp; B &lt;Docs&gt;</A>"))
        XCTAssertTrue(document.html.contains("<A HREF=\"https://openai.com\">OpenAI</A>"))
    }

    func testDocumentSkipsDuplicateInvalidAndUnavailableBookmarks() {
        let snapshot = MimicrySnapshot.browserImportFixture(
            sections: [
                SnapshotSection(
                    identifier: "firefox",
                    displayName: "Firefox",
                    items: [
                        browserSourceItem(identifier: "firefox", status: "captured"),
                        browserBookmarkItem(
                            key: "firefox.profile.0001.bookmark.0001",
                            title: "Docs",
                            folderPath: "Bookmarks Menu",
                            url: "https://example.com/docs"
                        ),
                        browserBookmarkItem(
                            key: "firefox.profile.0001.bookmark.0002",
                            title: "Docs",
                            folderPath: "Bookmarks Menu",
                            url: "https://example.com/docs"
                        ),
                        browserBookmarkItem(
                            key: "firefox.profile.0001.bookmark.0003",
                            title: "Local",
                            folderPath: "Bookmarks Menu",
                            url: "file:///Users/cmb/private.html"
                        ),
                        SnapshotItem(
                            key: "firefox.profile.0001.bookmark.0004",
                            value: .object([
                                "type": "folder",
                                "title": "Nested",
                                "folderPath": "Bookmarks Menu"
                            ]),
                            classification: .userMustReview,
                            applicability: .userSpecific
                        )
                    ]
                ),
                SnapshotSection(
                    identifier: "safari",
                    displayName: "Safari",
                    items: [
                        browserSourceItem(identifier: "safari", status: "unreadable"),
                        browserBookmarkItem(
                            key: "safari.bookmark.0001",
                            title: "Blocked",
                            folderPath: "Bookmarks Menu",
                            url: "https://blocked.example"
                        )
                    ]
                )
            ]
        )

        let document = BrowserBookmarkImportExporter().document(for: snapshot)

        XCTAssertEqual(document.summary.browserSectionCount, 2)
        XCTAssertEqual(document.summary.exportedBookmarkCount, 1)
        XCTAssertEqual(document.summary.skippedDuplicateCount, 1)
        XCTAssertEqual(document.summary.skippedInvalidCount, 2)
        XCTAssertEqual(document.summary.skippedUnavailableSourceCount, 1)
        XCTAssertTrue(document.html.contains("https://example.com/docs"))
        XCTAssertFalse(document.html.contains("file:///Users/cmb/private.html"))
        XCTAssertFalse(document.html.contains("https://blocked.example"))
    }

    func testExportWritesHTMLWithoutTouchingBrowserProfiles() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let outputURL = temporaryDirectory.appendingPathComponent("bookmarks.html")
        let snapshot = MimicrySnapshot.browserImportFixture(
            sections: [
                SnapshotSection(
                    identifier: "chrome",
                    displayName: "Chrome",
                    items: [
                        browserSourceItem(identifier: "chrome", status: "captured"),
                        browserBookmarkItem(
                            key: "chrome.profile.0001.bookmark.0001",
                            title: "Example",
                            folderPath: "Bookmarks Bar",
                            url: "https://example.com"
                        )
                    ]
                )
            ]
        )

        let result = try BrowserBookmarkImportExporter().export(snapshot: snapshot, to: outputURL)
        let html = try String(contentsOf: outputURL, encoding: .utf8)

        XCTAssertEqual(result.outputURL, outputURL)
        XCTAssertEqual(result.summary.exportedBookmarkCount, 1)
        XCTAssertTrue(html.contains("<A HREF=\"https://example.com\">Example</A>"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}

private extension MimicrySnapshot {
    static func browserImportFixture(sections: [SnapshotSection]) -> MimicrySnapshot {
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
