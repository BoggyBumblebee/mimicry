import MimicryCore
import XCTest

final class FirefoxBookmarksProviderTests: XCTestCase {
    func testSnapshotCapturesFirefoxBookmarkMetadataAcrossProfilesAndRedactsURLs() async throws {
        let firefoxRootURL = try makeFirefoxRootURL()
        let defaultPlacesURL = firefoxRootURL
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent("default-release", isDirectory: true)
            .appendingPathComponent("places.sqlite")
        let workPlacesURL = firefoxRootURL
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent("work", isDirectory: true)
            .appendingPathComponent("places.sqlite")
        let profilesINIURL = firefoxRootURL.appendingPathComponent("profiles.ini")
        let profilesINI = """
        [Profile1]
        Name=Work
        IsRelative=1
        Path=Profiles/work

        [Profile0]
        Name=default
        IsRelative=1
        Path=Profiles/default-release
        Default=1
        """
        let provider = FirefoxBookmarksProvider(
            firefoxRootURL: firefoxRootURL,
            fileExists: { url in
                [firefoxRootURL, profilesINIURL, defaultPlacesURL, workPlacesURL].contains(url)
            },
            textProvider: { _ in profilesINI },
            sqliteOutputProvider: { url in
                switch url {
                case defaultPlacesURL:
                    return firefoxRows([
                        FirefoxRow(id: 1, parentID: 0, type: 2, title: "", url: ""),
                        FirefoxRow(id: 2, parentID: 1, type: 2, title: "", url: ""),
                        FirefoxRow(id: 3, parentID: 1, type: 2, title: "Bookmarks Toolbar", url: ""),
                        FirefoxRow(id: 4, parentID: 2, type: 2, title: "Work", url: ""),
                        FirefoxRow(id: 5, parentID: 4, type: 1, title: "Example", url: "https://example.com/docs?token=secret#private")
                    ])
                case workPlacesURL:
                    return firefoxRows([
                        FirefoxRow(id: 1, parentID: 0, type: 2, title: "", url: ""),
                        FirefoxRow(id: 2, parentID: 1, type: 2, title: "Bookmarks Menu", url: ""),
                        FirefoxRow(id: 3, parentID: 2, type: 1, title: "OpenAI", url: "https://openai.com")
                    ])
                default:
                    return firefoxRows([])
                }
            }
        )

        let section = try await provider.snapshot(context: SnapshotContext(commandRunner: FakeCommandRunner()))

        XCTAssertEqual(section.identifier, "firefox")
        XCTAssertEqual(section.displayName, "Firefox")
        XCTAssertEqual(section.warnings.map(\.code), ["firefox.bookmark-urls-redacted"])
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "firefox.bookmarks.source",
                value: .object([
                    "path": firefoxRootURL.path,
                    "status": "captured",
                    "profileCount": "2",
                    "readableProfileCount": "2",
                    "unreadableProfileCount": "0",
                    "folderCount": "4",
                    "bookmarkCount": "2",
                    "redactedURLCount": "1"
                ]),
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "firefox.profile.0001.source",
                value: .object([
                    "profilePath": "Profiles/default-release",
                    "placesFile": "Profiles/default-release/places.sqlite",
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
                key: "firefox.profile.0001.folder.0001",
                value: .object([
                    "type": "folder",
                    "title": "Bookmarks Menu",
                    "path": "Bookmarks Menu"
                ]),
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "firefox.profile.0001.bookmark.0001",
                value: .object([
                    "type": "bookmark",
                    "title": "Example",
                    "folderPath": "Bookmarks Menu/Work",
                    "url": "https://example.com/docs",
                    "urlRedaction": "query,fragment"
                ]),
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "firefox.profile.0002.bookmark.0001",
                value: .object([
                    "type": "bookmark",
                    "title": "OpenAI",
                    "folderPath": "Bookmarks Menu",
                    "url": "https://openai.com",
                    "urlRedaction": "none"
                ]),
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ))
    }

    func testSnapshotReportsMissingFirefoxProfilesWithoutThrowing() async throws {
        let firefoxRootURL = try makeFirefoxRootURL()
        let provider = FirefoxBookmarksProvider(
            firefoxRootURL: firefoxRootURL,
            fileExists: { _ in false }
        )

        let section = try await provider.snapshot(context: SnapshotContext(commandRunner: FakeCommandRunner()))

        XCTAssertEqual(section.warnings.map(\.code), ["firefox.bookmarks-unavailable"])
        XCTAssertEqual(
            section.items,
            [
                SnapshotItem(
                    key: "firefox.bookmarks.source",
                    value: .object([
                        "path": firefoxRootURL.path,
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
        let firefoxRootURL = try makeFirefoxRootURL()
        let profilesINIURL = firefoxRootURL.appendingPathComponent("profiles.ini")
        let placesURL = firefoxRootURL
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent("default-release", isDirectory: true)
            .appendingPathComponent("places.sqlite")
        let provider = FirefoxBookmarksProvider(
            firefoxRootURL: firefoxRootURL,
            fileExists: { url in [firefoxRootURL, profilesINIURL, placesURL].contains(url) },
            textProvider: { _ in
                """
                [Profile0]
                IsRelative=1
                Path=Profiles/default-release
                """
            },
            sqliteOutputProvider: { _ in
                CommandResult(
                    executable: "",
                    arguments: [],
                    exitCode: 1,
                    standardError: "database is locked"
                )
            }
        )

        let section = try await provider.snapshot(context: SnapshotContext(commandRunner: FakeCommandRunner()))

        XCTAssertEqual(section.warnings.map(\.code), ["firefox.bookmarks-unreadable.0001"])
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "firefox.profile.0001.source",
                value: .object([
                    "profilePath": "Profiles/default-release",
                    "placesFile": "Profiles/default-release/places.sqlite",
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
        let firefoxRootURL = try makeFirefoxRootURL()
        let profilesINIURL = firefoxRootURL.appendingPathComponent("profiles.ini")
        let placesURL = firefoxRootURL
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent("default-release", isDirectory: true)
            .appendingPathComponent("places.sqlite")
        let provider = FirefoxBookmarksProvider(
            firefoxRootURL: firefoxRootURL,
            fileExists: { url in [firefoxRootURL, profilesINIURL, placesURL].contains(url) },
            textProvider: { _ in
                """
                [Profile0]
                IsRelative=1
                Path=Profiles/default-release
                """
            }
        )
        let detection = try await provider.detect(context: DetectionContext(commandRunner: FakeCommandRunner()))
        let valid = try await provider.validate(
            section: SnapshotSection(identifier: "firefox", displayName: "Firefox"),
            context: ValidationContext()
        )
        let invalid = try await provider.validate(
            section: SnapshotSection(identifier: "other", displayName: "Other"),
            context: ValidationContext()
        )
        let actions = try await provider.planApply(
            section: SnapshotSection(identifier: "firefox", displayName: "Firefox"),
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

    private func makeFirefoxRootURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}

private struct FirefoxRow {
    var id: Int
    var parentID: Int
    var type: Int
    var title: String
    var url: String
}

private func firefoxRows(_ rows: [FirefoxRow]) -> CommandResult {
    let separator = "\u{1F}"
    let output = rows
        .map { row in
            [
                String(row.id),
                String(row.parentID),
                String(row.type),
                row.title,
                row.url
            ].joined(separator: separator)
        }
        .joined(separator: "\n")

    return CommandResult(
        executable: "",
        arguments: [],
        exitCode: 0,
        standardOutput: output
    )
}
