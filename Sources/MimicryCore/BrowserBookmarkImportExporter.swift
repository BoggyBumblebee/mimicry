import Foundation

public struct BrowserBookmarkImportSummary: Equatable, Sendable {
    public var browserSectionCount: Int
    public var exportedBookmarkCount: Int
    public var skippedDuplicateCount: Int
    public var skippedInvalidCount: Int
    public var skippedUnavailableSourceCount: Int

    public init(
        browserSectionCount: Int = 0,
        exportedBookmarkCount: Int = 0,
        skippedDuplicateCount: Int = 0,
        skippedInvalidCount: Int = 0,
        skippedUnavailableSourceCount: Int = 0
    ) {
        self.browserSectionCount = browserSectionCount
        self.exportedBookmarkCount = exportedBookmarkCount
        self.skippedDuplicateCount = skippedDuplicateCount
        self.skippedInvalidCount = skippedInvalidCount
        self.skippedUnavailableSourceCount = skippedUnavailableSourceCount
    }
}

public struct BrowserBookmarkImportResult: Equatable, Sendable {
    public var outputURL: URL
    public var summary: BrowserBookmarkImportSummary

    public init(outputURL: URL, summary: BrowserBookmarkImportSummary) {
        self.outputURL = outputURL
        self.summary = summary
    }
}

public struct BrowserBookmarkImportDocument: Equatable, Sendable {
    public var html: String
    public var summary: BrowserBookmarkImportSummary

    public init(html: String, summary: BrowserBookmarkImportSummary) {
        self.html = html
        self.summary = summary
    }
}

public struct BrowserBookmarkImportExporter {
    private static let browserSectionIdentifiers = Set(["safari", "chrome", "firefox"])
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func export(snapshot: MimicrySnapshot, to outputURL: URL) throws -> BrowserBookmarkImportResult {
        let document = document(for: snapshot)
        let parentURL = outputURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        try Data(document.html.utf8).write(to: outputURL, options: .atomic)
        return BrowserBookmarkImportResult(outputURL: outputURL, summary: document.summary)
    }

    public func document(for snapshot: MimicrySnapshot) -> BrowserBookmarkImportDocument {
        let sections = snapshot.sections.filter { Self.browserSectionIdentifiers.contains($0.identifier) }
        var summary = BrowserBookmarkImportSummary(browserSectionCount: sections.count)
        var seenFingerprints: Set<BrowserBookmarkImportFingerprint> = []
        var entries: [BrowserBookmarkImportEntry] = []

        for section in sections {
            guard sourceIsAvailable(section) else {
                summary.skippedUnavailableSourceCount += 1
                continue
            }

            for item in section.items where item.key.contains(".bookmark.") {
                guard let bookmark = BrowserBookmarkImportBookmark(section: section, item: item) else {
                    summary.skippedInvalidCount += 1
                    continue
                }

                guard bookmark.hasImportableURL else {
                    summary.skippedInvalidCount += 1
                    continue
                }

                let fingerprint = BrowserBookmarkImportFingerprint(bookmark: bookmark)
                guard !seenFingerprints.contains(fingerprint) else {
                    summary.skippedDuplicateCount += 1
                    continue
                }

                seenFingerprints.insert(fingerprint)
                entries.append(BrowserBookmarkImportEntry(bookmark: bookmark))
                summary.exportedBookmarkCount += 1
            }
        }

        return BrowserBookmarkImportDocument(
            html: BrowserBookmarkImportHTMLRenderer(entries: entries).render(),
            summary: summary
        )
    }

    private func sourceIsAvailable(_ section: SnapshotSection) -> Bool {
        let sourceKey = "\(section.identifier).bookmarks.source"
        guard let item = section.items.first(where: { $0.key == sourceKey }),
              case let .object(values) = item.value,
              let status = values["status"]
        else {
            return true
        }

        return status != "absent" && status != "unreadable"
    }
}

private struct BrowserBookmarkImportBookmark: Equatable, Sendable {
    var browserName: String
    var title: String
    var folderPath: String
    var url: String

    init?(section: SnapshotSection, item: SnapshotItem) {
        guard case let .object(values) = item.value,
              values["type"] == "bookmark",
              let title = values["title"],
              let folderPath = values["folderPath"],
              let url = values["url"]
        else {
            return nil
        }

        self.browserName = section.displayName
        self.title = title
        self.folderPath = folderPath
        self.url = url
    }

    var hasImportableURL: Bool {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased()
        else {
            return false
        }

        return scheme == "http" || scheme == "https"
    }
}

private struct BrowserBookmarkImportFingerprint: Hashable, Sendable {
    var title: String
    var folderPath: String
    var url: String

    init(bookmark: BrowserBookmarkImportBookmark) {
        self.title = bookmark.title
        self.folderPath = bookmark.folderPath
        self.url = bookmark.url
    }
}

private struct BrowserBookmarkImportEntry: Equatable, Sendable {
    var bookmark: BrowserBookmarkImportBookmark
}

private struct BrowserBookmarkImportHTMLRenderer {
    var entries: [BrowserBookmarkImportEntry]

    func render() -> String {
        var lines = [
            "<!DOCTYPE NETSCAPE-Bookmark-file-1>",
            "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">",
            "<TITLE>Mimicry Browser Bookmarks</TITLE>",
            "<H1>Mimicry Browser Bookmarks</H1>",
            "<DL><p>"
        ]

        for browserGroup in groupedEntries() {
            lines.append("  <DT><H3>\(escape(browserGroup.browserName))</H3>")
            lines.append("  <DL><p>")

            for folderGroup in browserGroup.folders {
                lines.append("    <DT><H3>\(escape(folderGroup.folderPath))</H3>")
                lines.append("    <DL><p>")
                for entry in folderGroup.entries {
                    lines.append("      <DT><A HREF=\"\(escapeAttribute(entry.bookmark.url))\">\(escape(entry.bookmark.title))</A>")
                }
                lines.append("    </DL><p>")
            }

            lines.append("  </DL><p>")
        }

        lines.append("</DL><p>")
        return lines.joined(separator: "\n") + "\n"
    }

    private func groupedEntries() -> [BrowserBookmarkImportBrowserGroup] {
        let browserNames = Set(entries.map(\.bookmark.browserName)).sorted()
        return browserNames.map { browserName in
            let browserEntries = entries.filter { $0.bookmark.browserName == browserName }
            let folderPaths = Set(browserEntries.map(\.bookmark.folderPath)).sorted()
            let folders = folderPaths.map { folderPath in
                BrowserBookmarkImportFolderGroup(
                    folderPath: folderPath,
                    entries: browserEntries
                        .filter { $0.bookmark.folderPath == folderPath }
                        .sorted { lhs, rhs in
                            if lhs.bookmark.title == rhs.bookmark.title {
                                return lhs.bookmark.url < rhs.bookmark.url
                            }

                            return lhs.bookmark.title < rhs.bookmark.title
                        }
                )
            }

            return BrowserBookmarkImportBrowserGroup(browserName: browserName, folders: folders)
        }
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeAttribute(_ value: String) -> String {
        escape(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private struct BrowserBookmarkImportBrowserGroup: Equatable, Sendable {
    var browserName: String
    var folders: [BrowserBookmarkImportFolderGroup]
}

private struct BrowserBookmarkImportFolderGroup: Equatable, Sendable {
    var folderPath: String
    var entries: [BrowserBookmarkImportEntry]
}
