import Foundation

public struct SafariBookmarksProvider: ConfigurationProvider {
    public typealias FileExists = @Sendable (URL) -> Bool
    public typealias DataProvider = @Sendable (URL) throws -> Data

    public let identifier = "safari"
    public let displayName = "Safari"
    public let capabilities = ProviderCapabilities(canApply: false)

    private let bookmarksURL: URL
    private let fileExists: FileExists
    private let dataProvider: DataProvider

    public init(
        bookmarksURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Safari", isDirectory: true)
            .appendingPathComponent("Bookmarks.plist"),
        fileExists: @escaping FileExists = { FileManager.default.fileExists(atPath: $0.path) },
        dataProvider: @escaping DataProvider = { try Data(contentsOf: $0) }
    ) {
        self.bookmarksURL = bookmarksURL
        self.fileExists = fileExists
        self.dataProvider = dataProvider
    }

    public func detect(context _: DetectionContext) async throws -> DetectionResult {
        let isAvailable = fileExists(bookmarksURL)
        return DetectionResult(
            providerIdentifier: identifier,
            status: isAvailable ? .success : .warning,
            message: isAvailable
                ? "Safari bookmarks can be inspected."
                : "Safari bookmarks were not found."
        )
    }

    public func snapshot(context _: SnapshotContext) async throws -> SnapshotSection {
        guard fileExists(bookmarksURL) else {
            return unavailableSection()
        }

        do {
            let data = try dataProvider(bookmarksURL)
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let root = plist as? [String: Any] else {
                return unreadableSection(reason: "Safari bookmarks root was not a dictionary.")
            }

            let extraction = SafariBookmarkExtractor().extract(from: root)
            return SnapshotSection(
                identifier: identifier,
                displayName: displayName,
                items: [sourceItem(status: "captured", extraction: extraction)] + extraction.items,
                warnings: warnings(for: extraction)
            )
        } catch {
            return unreadableSection(reason: "Safari bookmarks could not be read.")
        }
    }

    public func validate(section: SnapshotSection, context _: ValidationContext) async throws -> ValidationResult {
        section.identifier == identifier
            ? ValidationResult(status: .success)
            : ValidationResult(status: .warning, messages: ["Expected Safari section."])
    }

    public func planApply(section _: SnapshotSection, context _: ApplyContext) async throws -> [PlannedAction] {
        [
            PlannedAction(
                providerIdentifier: identifier,
                kind: .requiresUserAction,
                summary: "Safari bookmark import planning starts after read-only bookmark inventory is trusted."
            )
        ]
    }

    public func apply(action: PlannedAction, context _: ApplyContext) async throws -> ApplyResult {
        ApplyResult(actionID: action.id, status: .skipped, message: "Safari bookmark apply is not implemented yet.")
    }

    private func unavailableSection() -> SnapshotSection {
        SnapshotSection(
            identifier: identifier,
            displayName: displayName,
            items: [
                sourceItem(status: "absent", extraction: .empty)
            ],
            warnings: [
                SnapshotWarning(
                    code: "safari.bookmarks-unavailable",
                    message: "Safari bookmarks were not found; no Safari bookmark data was captured."
                )
            ]
        )
    }

    private func unreadableSection(reason: String) -> SnapshotSection {
        SnapshotSection(
            identifier: identifier,
            displayName: displayName,
            items: [
                sourceItem(status: "unreadable", extraction: .empty)
            ],
            warnings: [
                SnapshotWarning(
                    code: "safari.bookmarks-unreadable",
                    message: reason
                )
            ]
        )
    }

    private func sourceItem(status: String, extraction: SafariBookmarkExtraction) -> SnapshotItem {
        SnapshotItem(
            key: "safari.bookmarks.source",
            value: .object([
                "path": "~/Library/Safari/Bookmarks.plist",
                "status": status,
                "folderCount": String(extraction.folderCount),
                "bookmarkCount": String(extraction.bookmarkCount),
                "redactedURLCount": String(extraction.redactedURLCount)
            ]),
            classification: .userMustReview,
            applicability: .userSpecific
        )
    }

    private func warnings(for extraction: SafariBookmarkExtraction) -> [SnapshotWarning] {
        guard extraction.redactedURLCount > 0 else {
            return []
        }

        return [
            SnapshotWarning(
                code: "safari.bookmark-urls-redacted",
                message: "\(extraction.redactedURLCount) Safari bookmark URL values had query strings or fragments removed before capture."
            )
        ]
    }
}

private struct SafariBookmarkExtractor {
    func extract(from root: [String: Any]) -> SafariBookmarkExtraction {
        guard let children = root["Children"] as? [[String: Any]] else {
            return .empty
        }

        var extraction = SafariBookmarkExtraction.empty
        for child in children {
            visit(child, path: [], extraction: &extraction)
        }
        return extraction
    }

    private func visit(_ node: [String: Any], path: [String], extraction: inout SafariBookmarkExtraction) {
        switch node["WebBookmarkType"] as? String {
        case "WebBookmarkTypeList":
            visitFolder(node, path: path, extraction: &extraction)
        case "WebBookmarkTypeLeaf":
            visitBookmark(node, path: path, extraction: &extraction)
        default:
            return
        }
    }

    private func visitFolder(_ node: [String: Any], path: [String], extraction: inout SafariBookmarkExtraction) {
        let title = displayTitle(from: node, fallback: "Untitled Folder")
        let folderPath = path + [title]
        let children = node["Children"] as? [[String: Any]] ?? []
        extraction.folderCount += 1
        extraction.items.append(
            item(
                key: "safari.folder.\(paddedIndex(extraction.folderCount))",
                object: [
                    "type": "folder",
                    "title": title,
                    "path": folderPath.joined(separator: "/"),
                    "childCount": String(children.count)
                ]
            )
        )

        for child in children {
            visit(child, path: folderPath, extraction: &extraction)
        }
    }

    private func visitBookmark(_ node: [String: Any], path: [String], extraction: inout SafariBookmarkExtraction) {
        let title = displayTitle(from: node, fallback: "Untitled Bookmark")
        let sanitizedURL = SafariBookmarkURLSanitizer().sanitize(node["URLString"] as? String)
        extraction.bookmarkCount += 1
        if sanitizedURL.didRedact {
            extraction.redactedURLCount += 1
        }

        extraction.items.append(
            item(
                key: "safari.bookmark.\(paddedIndex(extraction.bookmarkCount))",
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

    private func displayTitle(from node: [String: Any], fallback: String) -> String {
        if let title = node["Title"] as? String, let value = title.trimmedNilIfEmpty {
            return value
        }

        let uriDictionary = node["URIDictionary"] as? [String: Any]
        if let title = uriDictionary?["title"] as? String, let value = title.trimmedNilIfEmpty {
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

private struct SafariBookmarkURLSanitizer {
    func sanitize(_ rawValue: String?) -> SafariSanitizedURL {
        guard let rawValue, let trimmed = rawValue.trimmedNilIfEmpty else {
            return SafariSanitizedURL(value: "absent", redaction: "none")
        }

        guard var components = URLComponents(string: trimmed) else {
            return SafariSanitizedURL(value: "invalid", redaction: "invalid-url")
        }

        let hadQuery = components.query != nil
        let hadFragment = components.fragment != nil
        components.query = nil
        components.fragment = nil

        let redactions = [
            hadQuery ? "query" : nil,
            hadFragment ? "fragment" : nil
        ].compactMap { $0 }

        return SafariSanitizedURL(
            value: components.string ?? trimmed,
            redaction: redactions.isEmpty ? "none" : redactions.joined(separator: ",")
        )
    }
}

private struct SafariSanitizedURL: Equatable, Sendable {
    var value: String
    var redaction: String

    var didRedact: Bool {
        redaction != "none" && redaction != "invalid-url"
    }
}

private struct SafariBookmarkExtraction: Equatable, Sendable {
    var items: [SnapshotItem]
    var folderCount: Int
    var bookmarkCount: Int
    var redactedURLCount: Int

    static let empty = SafariBookmarkExtraction(
        items: [],
        folderCount: 0,
        bookmarkCount: 0,
        redactedURLCount: 0
    )
}
