import Foundation

public struct SnapshotApplyPlan: Equatable, Sendable {
    public var diff: SnapshotDiffReport
    public var actions: [PlannedAction]

    public init(diff: SnapshotDiffReport, actions: [PlannedAction]) {
        self.diff = diff
        self.actions = actions
    }

    public func count(_ kind: PlannedActionKind) -> Int {
        actions.filter { $0.kind == kind }.count
    }
}

public struct SnapshotApplyPlanner: Sendable {
    private static let informationalSectionIdentifiers = Set(["environment"])

    private let diffEngine: SnapshotDiffEngine

    public init(diffEngine: SnapshotDiffEngine = SnapshotDiffEngine()) {
        self.diffEngine = diffEngine
    }

    public func plan(reference: MimicrySnapshot, current: MimicrySnapshot) -> SnapshotApplyPlan {
        let diff = diffEngine.diff(reference: reference, current: current)
        let actions = diff.sections.flatMap { section in
            if Self.informationalSectionIdentifiers.contains(section.identifier) {
                return informationalActions(section: section)
            }

            if BrowserBookmarkApplyPlanner.isBrowserSection(section.identifier) {
                return BrowserBookmarkApplyPlanner(section: section).actions()
            }

            return section.items.compactMap { item in
                plannedAction(section: section, item: item)
            }
        }

        return SnapshotApplyPlan(diff: diff, actions: actions)
    }

    private func informationalActions(section: SnapshotSectionDiff) -> [PlannedAction] {
        guard section.items.contains(where: { $0.status != .matching }) else {
            return []
        }

        return [
            PlannedAction(
                providerIdentifier: section.identifier,
                kind: .skip,
                summary: "\(section.displayName) metadata is informational and is not applied."
            )
        ]
    }

    private func plannedAction(section: SnapshotSectionDiff, item: SnapshotItemDiff) -> PlannedAction? {
        switch item.status {
        case .matching:
            return nil
        case .changed, .missing:
            return changeAction(section: section, item: item)
        case .currentOnly:
            return PlannedAction(
                providerIdentifier: section.identifier,
                kind: .skip,
                summary: "\(item.key) exists on the current Mac but is not in the snapshot."
            )
        case .skipped:
            return PlannedAction(
                providerIdentifier: section.identifier,
                kind: .skip,
                summary: "\(item.key) is excluded from the snapshot and will not be applied."
            )
        case .unsupported:
            return PlannedAction(
                providerIdentifier: section.identifier,
                kind: .blocked,
                summary: "\(item.key) is marked unsupported."
            )
        }
    }

    private func changeAction(section: SnapshotSectionDiff, item: SnapshotItemDiff) -> PlannedAction {
        let kind = actionKind(for: section, item: item)
        return PlannedAction(
            providerIdentifier: section.identifier,
            kind: kind,
            summary: "\(item.key): \(summary(for: item))"
        )
    }

    private func actionKind(for section: SnapshotSectionDiff, item: SnapshotItemDiff) -> PlannedActionKind {
        switch item.classification {
        case .safeConfiguration:
            return installLike(section: section, item: item) ? .install : .configure
        case .potentiallySensitive, .userMustReview, .machineSpecific, .hardwareSpecific, .managed:
            return .requiresUserAction
        case .excluded:
            return .skip
        case .unsupported:
            return .blocked
        }
    }

    private func installLike(section: SnapshotSectionDiff, item: SnapshotItemDiff) -> Bool {
        section.identifier == "homebrew" && (
            item.key.hasPrefix("homebrew.tap.")
                || item.key.hasPrefix("homebrew.formula.")
                || item.key.hasPrefix("homebrew.cask.")
        )
    }

    private func summary(for item: SnapshotItemDiff) -> String {
        switch item.status {
        case .changed:
            return "would change from \(item.currentValue?.renderedDescription ?? "missing") to \(item.referenceValue?.renderedDescription ?? "absent")"
        case .missing:
            return "would add \(item.referenceValue?.renderedDescription ?? "absent")"
        case .matching:
            return "already matches"
        case .currentOnly:
            return "current-only"
        case .skipped:
            return "excluded"
        case .unsupported:
            return "unsupported"
        }
    }
}

private struct BrowserBookmarkApplyPlanner {
    private static let browserSectionIdentifiers = Set(["safari", "chrome", "firefox"])

    private let section: SnapshotSectionDiff

    init(section: SnapshotSectionDiff) {
        self.section = section
    }

    static func isBrowserSection(_ identifier: String) -> Bool {
        browserSectionIdentifiers.contains(identifier)
    }

    func actions() -> [PlannedAction] {
        let preview = preview()
        guard preview.hasWork else {
            return []
        }

        return [
            PlannedAction(
                providerIdentifier: section.identifier,
                kind: .requiresUserAction,
                summary: "\(section.displayName) bookmark import preview: \(preview.importableCount) importable, \(preview.alreadyPresentCount) already present, \(preview.skippedCount) skipped, \(preview.blockedCount) blocked; use export-browser-bookmarks to create a reviewable HTML handoff."
            )
        ]
    }

    private func preview() -> BrowserBookmarkApplyPreview {
        var preview = BrowserBookmarkApplyPreview()
        var seenReferenceFingerprints: Set<BrowserBookmarkFingerprint> = []
        let currentFingerprints = Set(section.items.compactMap(currentBookmarkFingerprint))

        for item in section.items {
            guard let referenceFingerprint = referenceBookmarkFingerprint(item) else {
                continue
            }

            guard !seenReferenceFingerprints.contains(referenceFingerprint) else {
                preview.skippedCount += 1
                continue
            }

            seenReferenceFingerprints.insert(referenceFingerprint)
            if currentFingerprints.contains(referenceFingerprint) {
                preview.alreadyPresentCount += 1
            } else {
                preview.importableCount += 1
            }
        }

        if let sourceStatus = referenceSourceStatus() {
            switch sourceStatus {
            case "absent":
                preview.skippedCount += 1
            case "unreadable":
                preview.blockedCount += 1
            default:
                break
            }
        }

        return preview
    }

    private func referenceBookmarkFingerprint(_ item: SnapshotItemDiff) -> BrowserBookmarkFingerprint? {
        guard item.key.contains(".bookmark.") else {
            return nil
        }

        return BrowserBookmarkFingerprint(value: item.referenceValue)
    }

    private func currentBookmarkFingerprint(_ item: SnapshotItemDiff) -> BrowserBookmarkFingerprint? {
        guard item.key.contains(".bookmark.") else {
            return nil
        }

        return BrowserBookmarkFingerprint(value: item.currentValue)
    }

    private func referenceSourceStatus() -> String? {
        let sourceKey = "\(section.identifier).bookmarks.source"
        guard let source = section.items.first(where: { $0.key == sourceKey })?.referenceValue,
              case let .object(values) = source
        else {
            return nil
        }

        return values["status"]
    }
}

private struct BrowserBookmarkApplyPreview: Equatable, Sendable {
    var importableCount = 0
    var alreadyPresentCount = 0
    var skippedCount = 0
    var blockedCount = 0

    var hasWork: Bool {
        importableCount > 0
            || alreadyPresentCount > 0
            || skippedCount > 0
            || blockedCount > 0
    }
}

private struct BrowserBookmarkFingerprint: Hashable, Sendable {
    var title: String
    var folderPath: String
    var url: String

    init?(value: SnapshotValue?) {
        guard case let .object(values) = value,
              values["type"] == "bookmark",
              let title = values["title"],
              let folderPath = values["folderPath"],
              let url = values["url"]
        else {
            return nil
        }

        self.title = title
        self.folderPath = folderPath
        self.url = url
    }
}
