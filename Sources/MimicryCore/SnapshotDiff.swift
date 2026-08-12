import Foundation

public struct SnapshotDiffReport: Equatable, Sendable {
    public var referenceSource: SnapshotSource
    public var currentSource: SnapshotSource
    public var sections: [SnapshotSectionDiff]

    public init(
        referenceSource: SnapshotSource,
        currentSource: SnapshotSource,
        sections: [SnapshotSectionDiff]
    ) {
        self.referenceSource = referenceSource
        self.currentSource = currentSource
        self.sections = sections
    }

    public var itemCount: Int {
        sections.reduce(0) { count, section in
            count + section.items.count
        }
    }

    public func count(_ status: SnapshotDiffStatus) -> Int {
        sections.reduce(0) { count, section in
            count + section.items.filter { $0.status == status }.count
        }
    }
}

public struct SnapshotSectionDiff: Equatable, Sendable, Identifiable {
    public var id: String { identifier }

    public var identifier: String
    public var displayName: String
    public var items: [SnapshotItemDiff]
    public var referenceWarnings: [SnapshotWarning]
    public var currentWarnings: [SnapshotWarning]

    public init(
        identifier: String,
        displayName: String,
        items: [SnapshotItemDiff],
        referenceWarnings: [SnapshotWarning] = [],
        currentWarnings: [SnapshotWarning] = []
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.items = items
        self.referenceWarnings = referenceWarnings
        self.currentWarnings = currentWarnings
    }
}

public struct SnapshotItemDiff: Equatable, Sendable, Identifiable {
    public var id: String { key }

    public var key: String
    public var status: SnapshotDiffStatus
    public var referenceValue: SnapshotValue?
    public var currentValue: SnapshotValue?
    public var classification: ConfigurationClassification
    public var applicability: ConfigurationApplicability

    public init(
        key: String,
        status: SnapshotDiffStatus,
        referenceValue: SnapshotValue?,
        currentValue: SnapshotValue?,
        classification: ConfigurationClassification,
        applicability: ConfigurationApplicability
    ) {
        self.key = key
        self.status = status
        self.referenceValue = referenceValue
        self.currentValue = currentValue
        self.classification = classification
        self.applicability = applicability
    }
}

public enum SnapshotDiffStatus: String, Equatable, Sendable {
    case matching
    case changed
    case missing
    case currentOnly
    case skipped
    case unsupported
}

public struct SnapshotDiffEngine: Sendable {
    private let comparesExcludedItems: Bool

    public init(comparesExcludedItems: Bool = false) {
        self.comparesExcludedItems = comparesExcludedItems
    }

    public func diff(reference: MimicrySnapshot, current: MimicrySnapshot) -> SnapshotDiffReport {
        let referenceSections = Dictionary(uniqueKeysWithValues: reference.sections.map { ($0.identifier, $0) })
        let currentSections = Dictionary(uniqueKeysWithValues: current.sections.map { ($0.identifier, $0) })
        let sectionIdentifiers = Set(referenceSections.keys)
            .union(currentSections.keys)
            .sorted()

        let sections = sectionIdentifiers.map { identifier in
            sectionDiff(
                identifier: identifier,
                reference: referenceSections[identifier],
                current: currentSections[identifier]
            )
        }

        return SnapshotDiffReport(
            referenceSource: reference.source,
            currentSource: current.source,
            sections: sections
        )
    }

    private func sectionDiff(
        identifier: String,
        reference: SnapshotSection?,
        current: SnapshotSection?
    ) -> SnapshotSectionDiff {
        let referenceItems = Dictionary(uniqueKeysWithValues: (reference?.items ?? []).map { ($0.key, $0) })
        let currentItems = Dictionary(uniqueKeysWithValues: (current?.items ?? []).map { ($0.key, $0) })
        let itemKeys = Set(referenceItems.keys)
            .union(currentItems.keys)
            .sorted()
        let items = itemKeys.map { key in
            itemDiff(key: key, reference: referenceItems[key], current: currentItems[key])
        }

        return SnapshotSectionDiff(
            identifier: identifier,
            displayName: reference?.displayName ?? current?.displayName ?? identifier,
            items: items,
            referenceWarnings: reference?.warnings ?? [],
            currentWarnings: current?.warnings ?? []
        )
    }

    private func itemDiff(key: String, reference: SnapshotItem?, current: SnapshotItem?) -> SnapshotItemDiff {
        if let reference {
            let status = status(reference: reference, current: current)
            return SnapshotItemDiff(
                key: reference.key,
                status: status,
                referenceValue: reference.value,
                currentValue: current?.value,
                classification: reference.classification,
                applicability: reference.applicability
            )
        }

        guard let current else {
            return SnapshotItemDiff(
                key: key,
                status: .missing,
                referenceValue: nil,
                currentValue: nil,
                classification: .unsupported,
                applicability: .universal
            )
        }

        return SnapshotItemDiff(
            key: current.key,
            status: .currentOnly,
            referenceValue: nil,
            currentValue: current.value,
            classification: current.classification,
            applicability: current.applicability
        )
    }

    private func status(reference: SnapshotItem, current: SnapshotItem?) -> SnapshotDiffStatus {
        switch reference.classification {
        case .excluded:
            guard comparesExcludedItems else {
                return .skipped
            }
            guard let current else {
                return .missing
            }
            return reference.value == current.value ? .matching : .changed
        case .unsupported:
            return .unsupported
        case .safeConfiguration, .potentiallySensitive, .userMustReview, .machineSpecific, .hardwareSpecific, .managed:
            guard let current else {
                return .missing
            }
            return reference.value == current.value ? .matching : .changed
        }
    }
}
