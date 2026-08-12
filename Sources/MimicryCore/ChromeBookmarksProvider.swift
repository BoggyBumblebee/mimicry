import Foundation

public struct ChromeBookmarksProvider: ConfigurationProvider {
    public typealias FileExists = @Sendable (URL) -> Bool
    public typealias DirectoryContents = @Sendable (URL) throws -> [URL]
    public typealias DataProvider = @Sendable (URL) throws -> Data

    public let identifier = "chrome"
    public let displayName = "Chrome"
    public let capabilities = ProviderCapabilities(canApply: false)

    private let chromeRootURL: URL
    private let fileExists: FileExists
    private let directoryContents: DirectoryContents
    private let dataProvider: DataProvider

    public init(
        chromeRootURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Google", isDirectory: true)
            .appendingPathComponent("Chrome", isDirectory: true),
        fileExists: @escaping FileExists = { FileManager.default.fileExists(atPath: $0.path) },
        directoryContents: @escaping DirectoryContents = {
            try FileManager.default.contentsOfDirectory(
                at: $0,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        },
        dataProvider: @escaping DataProvider = { try Data(contentsOf: $0) }
    ) {
        self.chromeRootURL = chromeRootURL
        self.fileExists = fileExists
        self.directoryContents = directoryContents
        self.dataProvider = dataProvider
    }

    public func detect(context _: DetectionContext) async throws -> DetectionResult {
        let profileCount = detectedProfiles().count
        return DetectionResult(
            providerIdentifier: identifier,
            status: profileCount > 0 ? .success : .warning,
            message: profileCount > 0
                ? "Chrome bookmark profiles can be inspected."
                : "Chrome bookmark profiles were not found."
        )
    }

    public func snapshot(context _: SnapshotContext) async throws -> SnapshotSection {
        let profiles = detectedProfiles()
        guard !profiles.isEmpty else {
            return unavailableSection()
        }

        var profileResults: [ChromeProfileBookmarkResult] = []
        for (offset, profile) in profiles.enumerated() {
            profileResults.append(snapshot(profile: profile, index: offset + 1))
        }

        let summary = ChromeBookmarkSummary(profileResults: profileResults)
        return SnapshotSection(
            identifier: identifier,
            displayName: displayName,
            items: [sourceItem(status: "captured", summary: summary)] + profileResults.flatMap(\.items),
            warnings: warnings(for: profileResults, summary: summary)
        )
    }

    public func validate(section: SnapshotSection, context _: ValidationContext) async throws -> ValidationResult {
        section.identifier == identifier
            ? ValidationResult(status: .success)
            : ValidationResult(status: .warning, messages: ["Expected Chrome section."])
    }

    public func planApply(section _: SnapshotSection, context _: ApplyContext) async throws -> [PlannedAction] {
        [
            PlannedAction(
                providerIdentifier: identifier,
                kind: .requiresUserAction,
                summary: "Chrome bookmark import planning starts after read-only multi-profile bookmark inventory is trusted."
            )
        ]
    }

    public func apply(action: PlannedAction, context _: ApplyContext) async throws -> ApplyResult {
        ApplyResult(actionID: action.id, status: .skipped, message: "Chrome bookmark apply is not implemented yet.")
    }

    private func detectedProfiles() -> [ChromeBookmarkProfile] {
        guard fileExists(chromeRootURL), let candidates = try? directoryContents(chromeRootURL) else {
            return []
        }

        return candidates
            .map { profileURL in
                ChromeBookmarkProfile(
                    relativePath: profileURL.lastPathComponent,
                    bookmarksURL: profileURL.appendingPathComponent("Bookmarks")
                )
            }
            .filter { fileExists($0.bookmarksURL) }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private func snapshot(profile: ChromeBookmarkProfile, index: Int) -> ChromeProfileBookmarkResult {
        do {
            let data = try dataProvider(profile.bookmarksURL)
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            guard let root = json as? [String: Any] else {
                return unreadableProfile(profile, index: index, reason: "Chrome bookmark root was not a dictionary.")
            }

            let extraction = ChromeBookmarkExtractor(profileIndex: index).extract(from: root)
            return ChromeProfileBookmarkResult(
                profile: profile,
                index: index,
                status: "captured",
                extraction: extraction,
                warning: nil
            )
        } catch {
            return unreadableProfile(profile, index: index, reason: "Chrome bookmarks could not be read for profile \(profile.relativePath).")
        }
    }

    private func unreadableProfile(
        _ profile: ChromeBookmarkProfile,
        index: Int,
        reason: String
    ) -> ChromeProfileBookmarkResult {
        ChromeProfileBookmarkResult(
            profile: profile,
            index: index,
            status: "unreadable",
            extraction: .empty,
            warning: SnapshotWarning(
                code: "chrome.bookmarks-unreadable.\(paddedIndex(index))",
                message: reason
            )
        )
    }

    private func unavailableSection() -> SnapshotSection {
        SnapshotSection(
            identifier: identifier,
            displayName: displayName,
            items: [
                sourceItem(status: "absent", summary: .empty)
            ],
            warnings: [
                SnapshotWarning(
                    code: "chrome.bookmarks-unavailable",
                    message: "Chrome bookmark profiles were not found; no Chrome bookmark data was captured."
                )
            ]
        )
    }

    private func sourceItem(status: String, summary: ChromeBookmarkSummary) -> SnapshotItem {
        SnapshotItem(
            key: "chrome.bookmarks.source",
            value: .object([
                "path": DisplayPathFormatter.userFacingPath(for: chromeRootURL),
                "status": status,
                "profileCount": String(summary.profileCount),
                "readableProfileCount": String(summary.readableProfileCount),
                "unreadableProfileCount": String(summary.unreadableProfileCount),
                "folderCount": String(summary.folderCount),
                "bookmarkCount": String(summary.bookmarkCount),
                "redactedURLCount": String(summary.redactedURLCount)
            ]),
            classification: .userMustReview,
            applicability: .userSpecific
        )
    }

    private func warnings(
        for profileResults: [ChromeProfileBookmarkResult],
        summary: ChromeBookmarkSummary
    ) -> [SnapshotWarning] {
        var values = profileResults.compactMap(\.warning)
        if summary.redactedURLCount > 0 {
            values.append(
                SnapshotWarning(
                    code: "chrome.bookmark-urls-redacted",
                    message: "\(summary.redactedURLCount) Chrome bookmark URL values had query strings or fragments removed before capture."
                )
            )
        }
        return values
    }

    private func paddedIndex(_ index: Int) -> String {
        String(format: "%04d", index)
    }
}

private struct ChromeBookmarkExtractor {
    private let profileIndex: Int
    private let sanitizer = BrowserBookmarkURLSanitizer()

    init(profileIndex: Int) {
        self.profileIndex = profileIndex
    }

    func extract(from root: [String: Any]) -> ChromeBookmarkExtraction {
        guard let roots = root["roots"] as? [String: Any] else {
            return .empty
        }

        var extraction = ChromeBookmarkExtraction.empty
        for rootKey in orderedRootKeys(from: roots) {
            guard let node = roots[rootKey] as? [String: Any] else {
                continue
            }
            visit(node, path: [], fallbackTitle: displayName(forRootKey: rootKey), extraction: &extraction)
        }
        return extraction
    }

    private func visit(
        _ node: [String: Any],
        path: [String],
        fallbackTitle: String,
        extraction: inout ChromeBookmarkExtraction
    ) {
        switch node["type"] as? String {
        case "folder":
            visitFolder(node, path: path, fallbackTitle: fallbackTitle, extraction: &extraction)
        case "url":
            visitBookmark(node, path: path, fallbackTitle: fallbackTitle, extraction: &extraction)
        default:
            return
        }
    }

    private func visitFolder(
        _ node: [String: Any],
        path: [String],
        fallbackTitle: String,
        extraction: inout ChromeBookmarkExtraction
    ) {
        let title = displayTitle(from: node, fallback: fallbackTitle)
        let folderPath = path + [title]
        let children = node["children"] as? [[String: Any]] ?? []
        extraction.folderCount += 1
        extraction.items.append(
            item(
                key: "chrome.profile.\(paddedIndex(profileIndex)).folder.\(paddedIndex(extraction.folderCount))",
                object: [
                    "type": "folder",
                    "title": title,
                    "path": folderPath.joined(separator: "/"),
                    "childCount": String(children.count)
                ]
            )
        )

        for child in children {
            visit(child, path: folderPath, fallbackTitle: "Untitled", extraction: &extraction)
        }
    }

    private func visitBookmark(
        _ node: [String: Any],
        path: [String],
        fallbackTitle: String,
        extraction: inout ChromeBookmarkExtraction
    ) {
        let title = displayTitle(from: node, fallback: fallbackTitle)
        let sanitizedURL = sanitizer.sanitize(node["url"] as? String)
        extraction.bookmarkCount += 1
        if sanitizedURL.didRedact {
            extraction.redactedURLCount += 1
        }

        extraction.items.append(
            item(
                key: "chrome.profile.\(paddedIndex(profileIndex)).bookmark.\(paddedIndex(extraction.bookmarkCount))",
                object: [
                    "type": "bookmark",
                    "title": title,
                    "folderPath": path.joined(separator: "/"),
                    "url": sanitizedURL.value,
                    "urlRedaction": sanitizedURL.redaction
                ]
            )
        )
    }

    private func orderedRootKeys(from roots: [String: Any]) -> [String] {
        let preferredOrder = ["bookmark_bar", "other", "synced"]
        let preferredKeys = preferredOrder.filter { roots[$0] != nil }
        let remainingKeys = roots.keys
            .filter { !preferredOrder.contains($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return preferredKeys + remainingKeys
    }

    private func displayName(forRootKey rootKey: String) -> String {
        switch rootKey {
        case "bookmark_bar":
            return "Bookmarks Bar"
        case "other":
            return "Other Bookmarks"
        case "synced":
            return "Mobile Bookmarks"
        default:
            return rootKey
        }
    }

    private func displayTitle(from node: [String: Any], fallback: String) -> String {
        if let name = node["name"] as? String, let value = name.trimmedNilIfEmpty {
            return value
        }

        return fallback
    }

    private func item(key: String, object: [String: String]) -> SnapshotItem {
        SnapshotItem(
            key: key,
            value: .object(object),
            classification: .userMustReview,
            applicability: .userSpecific
        )
    }

    private func paddedIndex(_ index: Int) -> String {
        String(format: "%04d", index)
    }
}

private struct ChromeBookmarkProfile: Equatable, Sendable {
    var relativePath: String
    var bookmarksURL: URL
}

private struct ChromeProfileBookmarkResult: Equatable, Sendable {
    var profile: ChromeBookmarkProfile
    var index: Int
    var status: String
    var extraction: ChromeBookmarkExtraction
    var warning: SnapshotWarning?

    var items: [SnapshotItem] {
        [profileItem] + extraction.items
    }

    private var profileItem: SnapshotItem {
        SnapshotItem(
            key: "chrome.profile.\(paddedIndex(index)).source",
            value: .object([
                "profileDirectory": profile.relativePath,
                "bookmarkFile": "\(profile.relativePath)/Bookmarks",
                "status": status,
                "folderCount": String(extraction.folderCount),
                "bookmarkCount": String(extraction.bookmarkCount),
                "redactedURLCount": String(extraction.redactedURLCount)
            ]),
            classification: .userMustReview,
            applicability: .userSpecific
        )
    }

    private func paddedIndex(_ index: Int) -> String {
        String(format: "%04d", index)
    }
}

private struct ChromeBookmarkSummary: Equatable, Sendable {
    var profileCount: Int
    var readableProfileCount: Int
    var unreadableProfileCount: Int
    var folderCount: Int
    var bookmarkCount: Int
    var redactedURLCount: Int

    init(profileResults: [ChromeProfileBookmarkResult]) {
        profileCount = profileResults.count
        readableProfileCount = profileResults.filter { $0.status == "captured" }.count
        unreadableProfileCount = profileResults.filter { $0.status == "unreadable" }.count
        folderCount = profileResults.reduce(0) { $0 + $1.extraction.folderCount }
        bookmarkCount = profileResults.reduce(0) { $0 + $1.extraction.bookmarkCount }
        redactedURLCount = profileResults.reduce(0) { $0 + $1.extraction.redactedURLCount }
    }

    static let empty = ChromeBookmarkSummary(
        profileCount: 0,
        readableProfileCount: 0,
        unreadableProfileCount: 0,
        folderCount: 0,
        bookmarkCount: 0,
        redactedURLCount: 0
    )

    private init(
        profileCount: Int,
        readableProfileCount: Int,
        unreadableProfileCount: Int,
        folderCount: Int,
        bookmarkCount: Int,
        redactedURLCount: Int
    ) {
        self.profileCount = profileCount
        self.readableProfileCount = readableProfileCount
        self.unreadableProfileCount = unreadableProfileCount
        self.folderCount = folderCount
        self.bookmarkCount = bookmarkCount
        self.redactedURLCount = redactedURLCount
    }
}

private struct ChromeBookmarkExtraction: Equatable, Sendable {
    var items: [SnapshotItem]
    var folderCount: Int
    var bookmarkCount: Int
    var redactedURLCount: Int

    static let empty = ChromeBookmarkExtraction(
        items: [],
        folderCount: 0,
        bookmarkCount: 0,
        redactedURLCount: 0
    )
}
