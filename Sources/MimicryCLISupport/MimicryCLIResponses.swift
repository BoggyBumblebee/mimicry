import Foundation
import MimicryCore

public enum MimicryCLIResponses {
    public static let phaseOneSubcommandNames = [
        "doctor",
        "snapshot",
        "inspect",
        "validate",
        "diff",
        "apply"
    ]

    public static func doctor(capabilities: MacCapabilities) -> String {
        let findings = DoctorFinding.findings(for: capabilities)
        let rows = findings.map { finding in
            "[\(finding.status.rawValue)] \(finding.title): \(finding.detail)"
        }

        return ([
            "Mimicry Doctor",
            "==============",
            "Host: \(capabilities.hostname)",
            "User: \(capabilities.username)",
            "macOS: \(capabilities.macOSVersion)",
            "Hardware: \(capabilities.hardwareModel)",
            "Architecture: \(capabilities.architecture.rawValue)",
            ""
        ] + rows + [
            "",
            "No system settings were changed."
        ]).joined(separator: "\n")
    }

    public static func snapshot(package: MimicryPackage) -> String {
        let warningCount = package.snapshot.sections.reduce(0) { count, section in
            count + section.warnings.count
        }

        return """
        Mimicry Snapshot Created
        ========================
        Package: \(package.url.path)
        Sections: \(package.snapshot.sections.count)
        Warnings: \(warningCount)
        No system settings were changed.
        """
    }

    public static func inspect(packagePath: String) throws -> String {
        let store = MimicryPackageStore()
        let package = try store.read(from: URL(fileURLWithPath: packagePath))
        return SnapshotInspectionReport(package: package).render()
    }

    public static func validate(packagePath: String) throws -> String {
        _ = try MimicryPackageStore().read(from: URL(fileURLWithPath: packagePath))
        return "Validation passed."
    }

    public static func diff(packagePath: String, currentSnapshot: MimicrySnapshot) throws -> String {
        let package = try MimicryPackageStore().read(from: URL(fileURLWithPath: packagePath))
        let report = SnapshotDiffEngine().diff(
            reference: package.snapshot,
            current: currentSnapshot
        )
        return SnapshotDiffReportRenderer(packagePath: packagePath, report: report).render()
    }

    public static func apply(
        packagePath: String,
        dryRun: Bool,
        currentSnapshot: MimicrySnapshot? = nil
    ) throws -> String {
        guard dryRun else {
            return """
            Mimicry Apply
            =============
            Snapshot: \(packagePath)
            Apply is not implemented yet. Use --dry-run to preview the action plan.
            No system settings were changed.
            """
        }

        let package = try MimicryPackageStore().read(from: URL(fileURLWithPath: packagePath))
        let currentSnapshot = currentSnapshot ?? package.snapshot
        let plan = SnapshotApplyPlanner().plan(
            reference: package.snapshot,
            current: currentSnapshot
        )
        return SnapshotApplyPlanRenderer(packagePath: packagePath, plan: plan).render()
    }

    public static func confirmedApply(packagePath: String, summary: FinderPreferenceApplySummary) -> String {
        var lines = [
            "Mimicry Apply",
            "=============",
            "Snapshot: \(packagePath)",
            "Mode: confirmed Finder-safe apply",
            "Backup: \(summary.backupURL?.path ?? "not needed")",
            "Applied: \(summary.results.filter { $0.status == .success }.count)",
            "Warnings: \(summary.results.filter { $0.status == .warning }.count)",
            "",
            "Results",
            "-------"
        ]

        if summary.results.isEmpty {
            lines.append("No safe Finder preference changes were required.")
        } else {
            for result in summary.results {
                lines.append("- \(result.status.rawValue): \(result.message)")
            }
        }

        lines.append("")
        lines.append("Only explicitly classified safe Finder preferences were considered.")
        return lines.joined(separator: "\n")
    }
}

private struct SnapshotApplyPlanRenderer {
    var packagePath: String
    var plan: SnapshotApplyPlan

    func render() -> String {
        var lines = [
            "Mimicry Apply Dry Run",
            "=====================",
            "Snapshot: \(packagePath)",
            "Reference: \(plan.diff.referenceSource.hostname) (\(plan.diff.referenceSource.username))",
            "Current: \(plan.diff.currentSource.hostname) (\(plan.diff.currentSource.username))",
            "Actions: \(plan.actions.count)",
            "",
            "Action Summary",
            "--------------"
        ]

        for kind in PlannedActionKind.displayOrder {
            lines.append("- \(kind.displayName): \(plan.count(kind))")
        }

        lines.append("")
        lines.append("Plan")
        lines.append("----")

        if plan.actions.isEmpty {
            lines.append("No actions are required.")
        } else {
            for kind in PlannedActionKind.displayOrder {
                let actions = plan.actions.filter { $0.kind == kind }
                guard !actions.isEmpty else {
                    continue
                }

                lines.append(kind.groupTitle)
                for action in actions {
                    lines.append("  - \(action.providerIdentifier): \(action.summary)")
                }
            }
        }

        lines.append("")
        lines.append("No system settings were changed.")
        return lines.joined(separator: "\n")
    }
}

private struct SnapshotDiffReportRenderer {
    var packagePath: String
    var report: SnapshotDiffReport

    func render() -> String {
        var lines = [
            "Mimicry Snapshot Diff",
            "=====================",
            "Snapshot: \(packagePath)",
            "Reference: \(report.referenceSource.hostname) (\(report.referenceSource.username))",
            "Current: \(report.currentSource.hostname) (\(report.currentSource.username))",
            "Sections: \(report.sections.count)",
            "Items: \(report.itemCount)",
            "",
            "Diff Summary",
            "------------"
        ]

        for status in SnapshotDiffStatus.displayOrder {
            lines.append("- \(status.displayName): \(report.count(status))")
        }

        lines.append("")
        lines.append("Sections")
        lines.append("--------")

        for section in report.sections {
            lines.append(contentsOf: sectionLines(section))
        }

        lines.append("")
        lines.append("No system settings were changed.")
        return lines.joined(separator: "\n")
    }

    private func sectionLines(_ section: SnapshotSectionDiff) -> [String] {
        var lines = [
            "\(section.displayName) (\(section.identifier))",
            "  Items: \(section.items.count)"
        ]

        for status in SnapshotDiffStatus.displayOrder {
            let items = section.items.filter { $0.status == status }
            guard !items.isEmpty else {
                continue
            }

            lines.append("  \(status.groupTitle)")
            lines.append(contentsOf: items.map(itemLine))
        }

        if !section.referenceWarnings.isEmpty {
            lines.append("  Snapshot Warnings")
            for warning in section.referenceWarnings {
                lines.append("    - \(warning.code): \(warning.message)")
            }
        }

        if !section.currentWarnings.isEmpty {
            lines.append("  Current Warnings")
            for warning in section.currentWarnings {
                lines.append("    - \(warning.code): \(warning.message)")
            }
        }

        return lines
    }

    private func itemLine(_ item: SnapshotItemDiff) -> String {
        let detail: String
        switch item.status {
        case .matching:
            detail = item.referenceValue?.renderedDescription ?? "absent"
        case .changed:
            detail = "\(item.referenceValue?.renderedDescription ?? "absent") -> \(item.currentValue?.renderedDescription ?? "absent")"
        case .missing:
            detail = "snapshot has \(item.referenceValue?.renderedDescription ?? "absent"); current is missing"
        case .currentOnly:
            detail = "current has \(item.currentValue?.renderedDescription ?? "absent"); not in snapshot"
        case .skipped:
            detail = "snapshot marks this item as excluded"
        case .unsupported:
            detail = "snapshot marks this item as unsupported"
        }

        return "    - \(item.key): \(detail) [\(item.classification.displayName), \(item.applicability.displayName)]"
    }
}

private struct SnapshotInspectionReport {
    var package: MimicryPackage

    func render() -> String {
        let snapshot = package.snapshot
        let itemCount = snapshot.sections.reduce(0) { count, section in
            count + section.items.count
        }
        let warningCount = snapshot.sections.reduce(0) { count, section in
            count + section.warnings.count
        }

        var lines = [
            "Mimicry Snapshot",
            "================",
            "Package: \(package.url.path)",
            "Schema version: \(snapshot.schemaVersion)",
            "Mimicry version: \(snapshot.mimicryVersion)",
            "Created: \(format(snapshot.createdAt))",
            "Source: \(snapshot.source.hostname) (\(snapshot.source.username))",
            "macOS: \(snapshot.source.macOSVersion)",
            "Hardware: \(snapshot.source.hardwareModel)",
            "Architecture: \(snapshot.source.architecture)",
            "Sections: \(snapshot.sections.count)",
            "Items: \(itemCount)",
            "Warnings: \(warningCount)",
            "",
            "Classification Summary",
            "----------------------"
        ]

        lines.append(contentsOf: countLines(
            counts: classificationCounts(in: snapshot),
            orderedKeys: ConfigurationClassification.allCases,
            label: { $0.displayName }
        ))
        lines.append("")
        lines.append("Applicability Summary")
        lines.append("---------------------")
        lines.append(contentsOf: countLines(
            counts: applicabilityCounts(in: snapshot),
            orderedKeys: ConfigurationApplicability.allCases,
            label: { $0.displayName }
        ))
        lines.append("")
        lines.append("Sections")
        lines.append("--------")

        for section in snapshot.sections {
            lines.append(contentsOf: sectionLines(section))
        }

        lines.append("")
        lines.append("No system settings were changed.")
        return lines.joined(separator: "\n")
    }

    private func sectionLines(_ section: SnapshotSection) -> [String] {
        var lines = [
            "\(section.displayName) (\(section.identifier))",
            "  Captured: \(format(section.capturedAt))",
            "  Items: \(section.items.count)",
            "  Warnings: \(section.warnings.count)"
        ]

        let captured = section.items.filter { $0.inspectionCategory == .captured }
        let review = section.items.filter { $0.inspectionCategory == .reviewRequired }
        let excluded = section.items.filter { $0.inspectionCategory == .excluded }
        let unsupported = section.items.filter { $0.inspectionCategory == .unsupported }

        lines.append(contentsOf: itemGroupLines(title: "Captured Items", items: captured))
        lines.append(contentsOf: itemGroupLines(title: "Review Required", items: review))
        lines.append(contentsOf: itemGroupLines(title: "Excluded Items", items: excluded))
        lines.append(contentsOf: itemGroupLines(title: "Unsupported Items", items: unsupported))

        if !section.warnings.isEmpty {
            lines.append("  Warnings")
            for warning in section.warnings {
                lines.append("    - \(warning.code): \(warning.message)")
            }
        }

        return lines
    }

    private func itemGroupLines(title: String, items: [SnapshotItem]) -> [String] {
        guard !items.isEmpty else {
            return []
        }

        return ["  \(title)"] + items.map { item in
            "    - \(item.key) = \(item.value.renderedDescription) [\(item.classification.displayName), \(item.applicability.displayName)]"
        }
    }

    private func classificationCounts(in snapshot: MimicrySnapshot) -> [ConfigurationClassification: Int] {
        var counts: [ConfigurationClassification: Int] = [:]
        for item in snapshot.sections.flatMap(\.items) {
            counts[item.classification, default: 0] += 1
        }
        return counts
    }

    private func applicabilityCounts(in snapshot: MimicrySnapshot) -> [ConfigurationApplicability: Int] {
        var counts: [ConfigurationApplicability: Int] = [:]
        for item in snapshot.sections.flatMap(\.items) {
            counts[item.applicability, default: 0] += 1
        }
        return counts
    }

    private func countLines<Key>(
        counts: [Key: Int],
        orderedKeys: [Key],
        label: (Key) -> String
    ) -> [String] where Key: Hashable {
        let lines = orderedKeys.compactMap { key -> String? in
            guard let count = counts[key], count > 0 else {
                return nil
            }
            return "- \(label(key)): \(count)"
        }

        return lines.isEmpty ? ["- None"] : lines
    }

    private func format(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private enum InspectionCategory {
    case captured
    case reviewRequired
    case excluded
    case unsupported
}

private extension SnapshotItem {
    var inspectionCategory: InspectionCategory {
        switch classification {
        case .excluded:
            return .excluded
        case .unsupported:
            return .unsupported
        case .potentiallySensitive, .userMustReview, .machineSpecific, .hardwareSpecific, .managed:
            return .reviewRequired
        case .safeConfiguration:
            return .captured
        }
    }
}

private extension ConfigurationClassification {
    static let allCases: [ConfigurationClassification] = [
        .safeConfiguration,
        .potentiallySensitive,
        .excluded,
        .userMustReview,
        .machineSpecific,
        .hardwareSpecific,
        .managed,
        .unsupported
    ]

    var displayName: String {
        switch self {
        case .safeConfiguration:
            return "safe configuration"
        case .potentiallySensitive:
            return "potentially sensitive"
        case .excluded:
            return "excluded"
        case .userMustReview:
            return "user must review"
        case .machineSpecific:
            return "machine specific"
        case .hardwareSpecific:
            return "hardware specific"
        case .managed:
            return "managed"
        case .unsupported:
            return "unsupported"
        }
    }
}

private extension SnapshotDiffStatus {
    static let displayOrder: [SnapshotDiffStatus] = [
        .matching,
        .changed,
        .missing,
        .currentOnly,
        .skipped,
        .unsupported
    ]

    var displayName: String {
        switch self {
        case .matching:
            return "matching"
        case .changed:
            return "changed"
        case .missing:
            return "missing"
        case .currentOnly:
            return "current only"
        case .skipped:
            return "skipped"
        case .unsupported:
            return "unsupported"
        }
    }

    var groupTitle: String {
        switch self {
        case .matching:
            return "Matching Items"
        case .changed:
            return "Changed Items"
        case .missing:
            return "Missing Items"
        case .currentOnly:
            return "Current-Only Items"
        case .skipped:
            return "Skipped Items"
        case .unsupported:
            return "Unsupported Items"
        }
    }
}

private extension PlannedActionKind {
    static let displayOrder: [PlannedActionKind] = [
        .install,
        .configure,
        .skip,
        .blocked,
        .requiresUserAction
    ]

    var displayName: String {
        switch self {
        case .install:
            return "install"
        case .configure:
            return "configure"
        case .skip:
            return "skip"
        case .blocked:
            return "blocked"
        case .requiresUserAction:
            return "requires user action"
        }
    }

    var groupTitle: String {
        switch self {
        case .install:
            return "INSTALL"
        case .configure:
            return "CONFIGURE"
        case .skip:
            return "SKIP"
        case .blocked:
            return "BLOCKED"
        case .requiresUserAction:
            return "REQUIRES USER ACTION"
        }
    }
}

private extension ConfigurationApplicability {
    static let allCases: [ConfigurationApplicability] = [
        .universal,
        .appleSiliconOnly,
        .intelOnly,
        .laptopOnly,
        .desktopOnly,
        .externalDisplayDependent,
        .externalInputDeviceDependent,
        .userSpecific,
        .machineSpecific,
        .managedDeviceOnly
    ]

    var displayName: String {
        switch self {
        case .universal:
            return "universal"
        case .appleSiliconOnly:
            return "Apple Silicon only"
        case .intelOnly:
            return "Intel only"
        case .laptopOnly:
            return "laptop only"
        case .desktopOnly:
            return "desktop only"
        case .externalDisplayDependent:
            return "external display dependent"
        case .externalInputDeviceDependent:
            return "external input device dependent"
        case .userSpecific:
            return "user specific"
        case .machineSpecific:
            return "machine specific"
        case .managedDeviceOnly:
            return "managed device only"
        }
    }
}

public struct DoctorFinding: Equatable, Sendable {
    public var status: DoctorFindingStatus
    public var title: String
    public var detail: String

    public init(status: DoctorFindingStatus, title: String, detail: String) {
        self.status = status
        self.title = title
        self.detail = detail
    }

    public static func findings(for capabilities: MacCapabilities) -> [DoctorFinding] {
        [
            DoctorFinding(
                status: .info,
                title: "macOS baseline",
                detail: "Mimicry is targeting macOS 15 and newer."
            ),
            DoctorFinding(
                status: capabilities.hasAdministratorPrivileges ? .pass : .warn,
                title: "Administrator access",
                detail: capabilities.hasAdministratorPrivileges
                    ? "Current user is in the admin group."
                    : "Some future apply actions may require an administrator account."
            ),
            DoctorFinding(
                status: capabilities.hasCommandLineTools ? .pass : .blocked,
                title: "Command Line Tools",
                detail: capabilities.hasCommandLineTools
                    ? "Xcode Command Line Tools are available."
                    : "Install Xcode Command Line Tools before provider detection."
            ),
            DoctorFinding(
                status: capabilities.xcodeVersion == nil ? .info : .pass,
                title: "Xcode",
                detail: capabilities.xcodeVersion ?? "Full Xcode was not detected; Command Line Tools may be enough for early workflows."
            ),
            DoctorFinding(
                status: capabilities.homebrew.isInstalled ? .pass : .warn,
                title: "Homebrew",
                detail: homebrewDetail(capabilities.homebrew)
            ),
            DoctorFinding(
                status: capabilities.hasMAS ? .pass : .warn,
                title: "mas CLI",
                detail: capabilities.hasMAS
                    ? "`mas` is available for App Store inventory."
                    : "`mas` is not available; App Store inventory will be limited until installed."
            ),
            DoctorFinding(
                status: stateStatus(capabilities.fileVaultState, available: .info, unavailable: .info),
                title: "FileVault",
                detail: stateDetail(capabilities.fileVaultState)
            ),
            DoctorFinding(
                status: stateStatus(capabilities.sipState, available: .pass, unavailable: .warn),
                title: "System Integrity Protection",
                detail: stateDetail(capabilities.sipState)
            ),
            DoctorFinding(
                status: stateStatus(capabilities.iCloudState, available: .info, unavailable: .info),
                title: "iCloud",
                detail: stateDetail(capabilities.iCloudState)
            ),
            DoctorFinding(
                status: stateStatus(capabilities.appStoreState, available: .info, unavailable: .info),
                title: "App Store",
                detail: stateDetail(capabilities.appStoreState)
            ),
            DoctorFinding(
                status: capabilities.managementState == .managed ? .warn : .info,
                title: "Device management",
                detail: stateDetail(capabilities.managementState)
            )
        ]
    }

    private static func homebrewDetail(_ homebrew: HomebrewCapability) -> String {
        guard homebrew.isInstalled else {
            return "Homebrew was not detected; Homebrew snapshots will be skipped."
        }

        var parts: [String] = []
        if let version = homebrew.version {
            parts.append(version)
        }
        if let prefix = homebrew.prefix {
            parts.append("prefix \(prefix)")
        }
        if homebrew.architecture != .unknown {
            parts.append("architecture \(homebrew.architecture.rawValue)")
        }

        return parts.isEmpty ? "Homebrew is available." : parts.joined(separator: ", ")
    }

    private static func stateStatus(
        _ state: CapabilityState,
        available: DoctorFindingStatus,
        unavailable: DoctorFindingStatus
    ) -> DoctorFindingStatus {
        switch state {
        case .available, .enabled:
            return available
        case .unavailable, .disabled, .unsupported:
            return unavailable
        case .managed, .requiresUserAction:
            return .warn
        case .unknown:
            return .info
        }
    }

    private static func stateDetail(_ state: CapabilityState) -> String {
        switch state {
        case .available:
            return "Available."
        case .unavailable:
            return "Not available."
        case .enabled:
            return "Enabled."
        case .disabled:
            return "Disabled."
        case .managed:
            return "Managed by organization policy."
        case .requiresUserAction:
            return "Requires user action or sign-in."
        case .unsupported:
            return "Unsupported on this Mac."
        case .unknown:
            return "State could not be determined."
        }
    }
}

public enum DoctorFindingStatus: String, Equatable, Sendable {
    case pass = "PASS"
    case warn = "WARN"
    case info = "INFO"
    case blocked = "BLOCKED"
}
