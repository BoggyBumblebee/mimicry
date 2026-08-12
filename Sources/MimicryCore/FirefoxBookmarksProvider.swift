import Foundation

public struct FirefoxBookmarksProvider: ConfigurationProvider {
    public typealias FileExists = @Sendable (URL) -> Bool
    public typealias DirectoryContents = @Sendable (URL) throws -> [URL]
    public typealias TextProvider = @Sendable (URL) throws -> String
    public typealias SQLiteOutputProvider = @Sendable (URL) async throws -> CommandResult

    public let identifier = "firefox"
    public let displayName = "Firefox"
    public let capabilities = ProviderCapabilities(canApply: false)

    private let firefoxRootURL: URL
    private let sqlite3URL: URL
    private let fileExists: FileExists
    private let directoryContents: DirectoryContents
    private let textProvider: TextProvider
    private let sqliteOutputProvider: SQLiteOutputProvider?

    public init(
        firefoxRootURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Firefox", isDirectory: true),
        sqlite3URL: URL = SystemToolPathFactory.usrBin("sqlite3"),
        fileExists: @escaping FileExists = { FileManager.default.fileExists(atPath: $0.path) },
        directoryContents: @escaping DirectoryContents = {
            try FileManager.default.contentsOfDirectory(
                at: $0,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        },
        textProvider: @escaping TextProvider = { try String(contentsOf: $0, encoding: .utf8) },
        sqliteOutputProvider: SQLiteOutputProvider? = nil
    ) {
        self.firefoxRootURL = firefoxRootURL
        self.sqlite3URL = sqlite3URL
        self.fileExists = fileExists
        self.directoryContents = directoryContents
        self.textProvider = textProvider
        self.sqliteOutputProvider = sqliteOutputProvider
    }

    public func detect(context _: DetectionContext) async throws -> DetectionResult {
        let profileCount = detectedProfiles().count
        return DetectionResult(
            providerIdentifier: identifier,
            status: profileCount > 0 ? .success : .warning,
            message: profileCount > 0
                ? "Firefox bookmark profiles can be inspected."
                : "Firefox bookmark profiles were not found."
        )
    }

    public func snapshot(context: SnapshotContext) async throws -> SnapshotSection {
        let profiles = detectedProfiles()
        guard !profiles.isEmpty else {
            return unavailableSection()
        }

        var profileResults: [FirefoxProfileBookmarkResult] = []
        for (offset, profile) in profiles.enumerated() {
            profileResults.append(await snapshot(profile: profile, index: offset + 1, context: context))
        }

        let summary = FirefoxBookmarkSummary(profileResults: profileResults)
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
            : ValidationResult(status: .warning, messages: ["Expected Firefox section."])
    }

    public func planApply(section _: SnapshotSection, context _: ApplyContext) async throws -> [PlannedAction] {
        [
            PlannedAction(
                providerIdentifier: identifier,
                kind: .requiresUserAction,
                summary: "Firefox bookmark import planning starts after read-only multi-profile bookmark inventory is trusted."
            )
        ]
    }

    public func apply(action: PlannedAction, context _: ApplyContext) async throws -> ApplyResult {
        ApplyResult(actionID: action.id, status: .skipped, message: "Firefox bookmark apply is not implemented yet.")
    }

    private func detectedProfiles() -> [FirefoxBookmarkProfile] {
        let profiles = profilesFromConfiguration() + profilesFromProfilesDirectory()
        var seen: Set<String> = []
        return profiles
            .filter { fileExists($0.placesURL) }
            .filter { profile in
                let key = profile.placesURL.standardizedFileURL.path
                guard !seen.contains(key) else {
                    return false
                }
                seen.insert(key)
                return true
            }
            .sorted { $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending }
    }

    private func profilesFromConfiguration() -> [FirefoxBookmarkProfile] {
        let profilesIniURL = firefoxRootURL.appendingPathComponent("profiles.ini")
        guard fileExists(profilesIniURL), let contents = try? textProvider(profilesIniURL) else {
            return []
        }

        return FirefoxProfilesINIParser(firefoxRootURL: firefoxRootURL).profiles(from: contents)
    }

    private func profilesFromProfilesDirectory() -> [FirefoxBookmarkProfile] {
        let profilesURL = firefoxRootURL.appendingPathComponent("Profiles", isDirectory: true)
        guard fileExists(profilesURL), let candidates = try? directoryContents(profilesURL) else {
            return []
        }

        return candidates.map { profileURL in
            FirefoxBookmarkProfile(
                displayPath: "Profiles/\(profileURL.lastPathComponent)",
                placesURL: profileURL.appendingPathComponent("places.sqlite")
            )
        }
    }

    private func snapshot(
        profile: FirefoxBookmarkProfile,
        index: Int,
        context: SnapshotContext
    ) async -> FirefoxProfileBookmarkResult {
        do {
            let result = try await sqliteOutput(for: profile.placesURL, context: context)
            guard result.exitCode == 0 else {
                return unreadableProfile(profile, index: index, reason: "Firefox bookmarks could not be read for profile \(profile.displayPath).")
            }

            let rows = try FirefoxSQLiteBookmarkOutputParser().rows(from: result.standardOutput)
            let extraction = FirefoxBookmarkExtractor(profileIndex: index).extract(from: rows)
            return FirefoxProfileBookmarkResult(
                profile: profile,
                index: index,
                status: "captured",
                extraction: extraction,
                warning: nil
            )
        } catch {
            return unreadableProfile(profile, index: index, reason: "Firefox bookmarks could not be read for profile \(profile.displayPath).")
        }
    }

    private func sqliteOutput(for placesURL: URL, context: SnapshotContext) async throws -> CommandResult {
        if let sqliteOutputProvider {
            return try await sqliteOutputProvider(placesURL)
        }

        return try await context.commandRunner.run(
            executable: sqlite3URL,
            arguments: [
                "-readonly",
                "-noheader",
                "-separator",
                FirefoxSQLiteBookmarkOutputParser.separator,
                placesURL.path,
                FirefoxBookmarkSQLiteQuery.bookmarkRows
            ],
            environment: nil
        )
    }

    private func unreadableProfile(
        _ profile: FirefoxBookmarkProfile,
        index: Int,
        reason: String
    ) -> FirefoxProfileBookmarkResult {
        FirefoxProfileBookmarkResult(
            profile: profile,
            index: index,
            status: "unreadable",
            extraction: .empty,
            warning: SnapshotWarning(
                code: "firefox.bookmarks-unreadable.\(paddedIndex(index))",
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
                    code: "firefox.bookmarks-unavailable",
                    message: "Firefox bookmark profiles were not found; no Firefox bookmark data was captured."
                )
            ]
        )
    }

    private func sourceItem(status: String, summary: FirefoxBookmarkSummary) -> SnapshotItem {
        SnapshotItem(
            key: "firefox.bookmarks.source",
            value: .object([
                "path": DisplayPathFormatter.userFacingPath(for: firefoxRootURL),
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
        for profileResults: [FirefoxProfileBookmarkResult],
        summary: FirefoxBookmarkSummary
    ) -> [SnapshotWarning] {
        var values = profileResults.compactMap(\.warning)
        if summary.redactedURLCount > 0 {
            values.append(
                SnapshotWarning(
                    code: "firefox.bookmark-urls-redacted",
                    message: "\(summary.redactedURLCount) Firefox bookmark URL values had query strings or fragments removed before capture."
                )
            )
        }
        return values
    }

    private func paddedIndex(_ index: Int) -> String {
        String(format: "%04d", index)
    }
}

private enum FirefoxBookmarkSQLiteQuery {
    static let bookmarkRows = """
    SELECT b.id, b.parent, b.type,
    replace(replace(replace(COALESCE(NULLIF(b.title, ''), ''), char(31), ' '), char(10), ' '), char(13), ' '),
    replace(replace(replace(COALESCE(p.url, ''), char(31), ' '), char(10), ' '), char(13), ' ')
    FROM moz_bookmarks b
    LEFT JOIN moz_places p ON b.fk = p.id
    WHERE b.type IN (1, 2)
    ORDER BY b.parent, b.position, b.id;
    """
}

private struct FirefoxProfilesINIParser {
    private let firefoxRootURL: URL

    init(firefoxRootURL: URL) {
        self.firefoxRootURL = firefoxRootURL
    }

    func profiles(from contents: String) -> [FirefoxBookmarkProfile] {
        profileSections(from: contents).compactMap(profile(from:))
    }

    private func profileSections(from contents: String) -> [[String: String]] {
        var sections: [[String: String]] = []
        var current: [String: String] = [:]
        var isProfileSection = false

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix(";"), !line.hasPrefix("#") else {
                continue
            }

            if line.hasPrefix("["), line.hasSuffix("]") {
                if isProfileSection {
                    sections.append(current)
                }
                current = [:]
                isProfileSection = line.lowercased().hasPrefix("[profile")
                continue
            }

            guard isProfileSection, let separator = line.firstIndex(of: "=") else {
                continue
            }

            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            current[key] = value
        }

        if isProfileSection {
            sections.append(current)
        }
        return sections
    }

    private func profile(from section: [String: String]) -> FirefoxBookmarkProfile? {
        guard let rawPath = section["Path"]?.trimmedNilIfEmpty else {
            return nil
        }

        let isRelative = section["IsRelative"] != "0"
        let profileURL = isRelative
            ? firefoxRootURL.appendingPathComponent(rawPath, isDirectory: true)
            : URL(fileURLWithPath: rawPath, isDirectory: true)
        let displayPath = isRelative
            ? rawPath
            : DisplayPathFormatter.userFacingPath(for: profileURL)
        return FirefoxBookmarkProfile(
            displayPath: displayPath,
            placesURL: profileURL.appendingPathComponent("places.sqlite")
        )
    }
}

private struct FirefoxSQLiteBookmarkOutputParser {
    static let separator = "\u{1F}"

    func rows(from output: String) throws -> [FirefoxBookmarkRow] {
        try output
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .map(row(from:))
    }

    private func row(from line: String) throws -> FirefoxBookmarkRow {
        let fields = line.split(
            separator: Character(Self.separator),
            omittingEmptySubsequences: false
        ).map(String.init)
        guard fields.count == 5,
              let id = Int(fields[0]),
              let parentID = Int(fields[1]),
              let type = Int(fields[2])
        else {
            throw FirefoxBookmarkParseError.invalidRow
        }

        return FirefoxBookmarkRow(
            id: id,
            parentID: parentID,
            type: type,
            title: fields[3],
            url: fields[4]
        )
    }
}

private enum FirefoxBookmarkParseError: Error {
    case invalidRow
}

private struct FirefoxBookmarkExtractor {
    private let profileIndex: Int
    private let sanitizer = BrowserBookmarkURLSanitizer()

    init(profileIndex: Int) {
        self.profileIndex = profileIndex
    }

    func extract(from rows: [FirefoxBookmarkRow]) -> FirefoxBookmarkExtraction {
        var extraction = FirefoxBookmarkExtraction.empty
        let rowsByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })

        for row in rows {
            switch row.type {
            case FirefoxBookmarkType.folder:
                visitFolder(row, rowsByID: rowsByID, extraction: &extraction)
            case FirefoxBookmarkType.bookmark:
                visitBookmark(row, rowsByID: rowsByID, extraction: &extraction)
            default:
                continue
            }
        }
        return extraction
    }

    private func visitFolder(
        _ row: FirefoxBookmarkRow,
        rowsByID: [Int: FirefoxBookmarkRow],
        extraction: inout FirefoxBookmarkExtraction
    ) {
        guard row.id != FirefoxBookmarkRootID.root else {
            return
        }

        let folderPath = folderPath(for: row.id, rowsByID: rowsByID)
        extraction.folderCount += 1
        extraction.items.append(
            item(
                key: "firefox.profile.\(paddedIndex(profileIndex)).folder.\(paddedIndex(extraction.folderCount))",
                object: [
                    "type": "folder",
                    "title": folderPath.last ?? folderTitle(for: row),
                    "path": folderPath.joined(separator: "/")
                ]
            )
        )
    }

    private func visitBookmark(
        _ row: FirefoxBookmarkRow,
        rowsByID: [Int: FirefoxBookmarkRow],
        extraction: inout FirefoxBookmarkExtraction
    ) {
        let title = displayTitle(for: row, fallback: "Untitled Bookmark")
        let sanitizedURL = sanitizer.sanitize(row.url)
        extraction.bookmarkCount += 1
        if sanitizedURL.didRedact {
            extraction.redactedURLCount += 1
        }

        extraction.items.append(
            item(
                key: "firefox.profile.\(paddedIndex(profileIndex)).bookmark.\(paddedIndex(extraction.bookmarkCount))",
                object: [
                    "type": "bookmark",
                    "title": title,
                    "folderPath": folderPath(for: row.parentID, rowsByID: rowsByID).joined(separator: "/"),
                    "url": sanitizedURL.value,
                    "urlRedaction": sanitizedURL.redaction
                ]
            )
        )
    }

    private func folderPath(
        for folderID: Int,
        rowsByID: [Int: FirefoxBookmarkRow],
        visited: Set<Int> = []
    ) -> [String] {
        guard folderID != FirefoxBookmarkRootID.root,
              !visited.contains(folderID),
              let row = rowsByID[folderID],
              row.type == FirefoxBookmarkType.folder
        else {
            return []
        }

        let parentPath = folderPath(
            for: row.parentID,
            rowsByID: rowsByID,
            visited: visited.union([folderID])
        )
        return parentPath + [folderTitle(for: row)]
    }

    private func folderTitle(for row: FirefoxBookmarkRow) -> String {
        if row.parentID == FirefoxBookmarkRootID.root, isKnownRootFolder(row.id) {
            return rootFolderName(for: row.id)
        }

        return displayTitle(for: row, fallback: "Untitled Folder")
    }

    private func displayTitle(for row: FirefoxBookmarkRow, fallback: String) -> String {
        row.title.trimmedNilIfEmpty ?? fallback
    }

    private func isKnownRootFolder(_ id: Int) -> Bool {
        [
            FirefoxBookmarkRootID.menu,
            FirefoxBookmarkRootID.toolbar,
            FirefoxBookmarkRootID.tags,
            FirefoxBookmarkRootID.other,
            FirefoxBookmarkRootID.mobile
        ].contains(id)
    }

    private func rootFolderName(for id: Int) -> String {
        switch id {
        case FirefoxBookmarkRootID.menu:
            return "Bookmarks Menu"
        case FirefoxBookmarkRootID.toolbar:
            return "Bookmarks Toolbar"
        case FirefoxBookmarkRootID.tags:
            return "Tags"
        case FirefoxBookmarkRootID.other:
            return "Other Bookmarks"
        case FirefoxBookmarkRootID.mobile:
            return "Mobile Bookmarks"
        default:
            return "Untitled Folder"
        }
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

private enum FirefoxBookmarkType {
    static let bookmark = 1
    static let folder = 2
}

private enum FirefoxBookmarkRootID {
    static let root = 1
    static let menu = 2
    static let toolbar = 3
    static let tags = 4
    static let other = 5
    static let mobile = 6
}

private struct FirefoxBookmarkProfile: Equatable, Sendable {
    var displayPath: String
    var placesURL: URL
}

private struct FirefoxBookmarkRow: Equatable, Sendable {
    var id: Int
    var parentID: Int
    var type: Int
    var title: String
    var url: String
}

private struct FirefoxProfileBookmarkResult: Equatable, Sendable {
    var profile: FirefoxBookmarkProfile
    var index: Int
    var status: String
    var extraction: FirefoxBookmarkExtraction
    var warning: SnapshotWarning?

    var items: [SnapshotItem] {
        [profileItem] + extraction.items
    }

    private var profileItem: SnapshotItem {
        SnapshotItem(
            key: "firefox.profile.\(paddedIndex(index)).source",
            value: .object([
                "profilePath": profile.displayPath,
                "placesFile": "\(profile.displayPath)/places.sqlite",
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

private struct FirefoxBookmarkSummary: Equatable, Sendable {
    var profileCount: Int
    var readableProfileCount: Int
    var unreadableProfileCount: Int
    var folderCount: Int
    var bookmarkCount: Int
    var redactedURLCount: Int

    init(profileResults: [FirefoxProfileBookmarkResult]) {
        profileCount = profileResults.count
        readableProfileCount = profileResults.filter { $0.status == "captured" }.count
        unreadableProfileCount = profileResults.filter { $0.status == "unreadable" }.count
        folderCount = profileResults.reduce(0) { $0 + $1.extraction.folderCount }
        bookmarkCount = profileResults.reduce(0) { $0 + $1.extraction.bookmarkCount }
        redactedURLCount = profileResults.reduce(0) { $0 + $1.extraction.redactedURLCount }
    }

    static let empty = FirefoxBookmarkSummary(
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

private struct FirefoxBookmarkExtraction: Equatable, Sendable {
    var items: [SnapshotItem]
    var folderCount: Int
    var bookmarkCount: Int
    var redactedURLCount: Int

    static let empty = FirefoxBookmarkExtraction(
        items: [],
        folderCount: 0,
        bookmarkCount: 0,
        redactedURLCount: 0
    )
}
