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
    private let diffEngine: SnapshotDiffEngine

    public init(diffEngine: SnapshotDiffEngine = SnapshotDiffEngine()) {
        self.diffEngine = diffEngine
    }

    public func plan(reference: MimicrySnapshot, current: MimicrySnapshot) -> SnapshotApplyPlan {
        let diff = diffEngine.diff(reference: reference, current: current)
        let actions = diff.sections.flatMap { section in
            section.items.compactMap { item in
                plannedAction(section: section, item: item)
            }
        }

        return SnapshotApplyPlan(diff: diff, actions: actions)
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
