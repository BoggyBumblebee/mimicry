import Combine
import Foundation
import MimicryCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshotState: AppCommandState<AppSnapshotSummary> = .idle
    @Published private(set) var packageState: AppCommandState<AppPackageSummary> = .idle
    @Published private(set) var compareState: AppCommandState<AppCompareSummary> = .idle
    @Published private(set) var applyPlanState: AppCommandState<AppApplyPlanSummary> = .idle
    @Published private(set) var confirmedApplyState: AppCommandState<AppConfirmedApplySummary> = .idle
    @Published private(set) var browserBookmarkExportState: AppCommandState<AppBrowserBookmarkExportSummary> = .idle
    @Published private(set) var auditExportState: AppCommandState<AppAuditExportSummary> = .idle
    @Published private(set) var diagnosticsState: AppCommandState<AppDiagnosticsSummary> = .idle
    @Published private(set) var auditLog: [AppAuditLogEntry] = []
    @Published private(set) var recentPackages: [RecentPackage]

    private let runtime: AppRuntime
    private let historyStore: PackageHistoryStore

    init(
        runtime: AppRuntime = .live,
        historyStore: PackageHistoryStore = .userDefaults()
    ) {
        self.runtime = runtime
        self.historyStore = historyStore
        recentPackages = historyStore.load()
    }

    func createSnapshot(to outputURL: URL) async {
        snapshotState = .running

        do {
            let summary = try await runtime.createSnapshot(outputURL.standardizedFileURL)
            snapshotState = .succeeded(summary)
            packageState = .running
            compareState = .idle
            applyPlanState = .idle
            confirmedApplyState = .idle
            browserBookmarkExportState = .idle
            do {
                packageState = .succeeded(try await runtime.openPackage(summary.url))
            } catch {
                packageState = .failed(error.readableMessage)
            }
            recentPackages = historyStore.record(summary.url)
            recordAudit(
                operation: .snapshot,
                status: "success",
                packageURL: summary.url,
                message: "Created snapshot package.",
                metrics: [
                    "sections": summary.sectionCount,
                    "items": summary.itemCount,
                    "warnings": summary.warningCount
                ]
            )
        } catch {
            snapshotState = .failed(error.readableMessage)
            recordAudit(
                operation: .snapshot,
                status: "failed",
                packageURL: outputURL.standardizedFileURL,
                message: error.readableMessage
            )
        }
    }

    func openPackage(at packageURL: URL) async {
        packageState = .running
        compareState = .idle
        applyPlanState = .idle
        confirmedApplyState = .idle
        browserBookmarkExportState = .idle

        do {
            let summary = try await runtime.openPackage(packageURL.standardizedFileURL)
            packageState = .succeeded(summary)
            recentPackages = historyStore.record(summary.url)
            recordAudit(
                operation: .openPackage,
                status: "success",
                packageURL: summary.url,
                message: "Opened and validated package.",
                metrics: [
                    "sections": summary.sectionCount,
                    "items": summary.itemCount,
                    "warnings": summary.warningCount
                ]
            )
        } catch {
            packageState = .failed(error.readableMessage)
            recordAudit(
                operation: .openPackage,
                status: "failed",
                packageURL: packageURL.standardizedFileURL,
                message: error.readableMessage
            )
        }
    }

    func exportBrowserBookmarksForCurrentPackage(to outputURL: URL) async {
        guard case let .succeeded(package) = packageState else {
            browserBookmarkExportState = .failed("Open a package before exporting browser bookmarks.")
            recordAudit(
                operation: .browserBookmarkExport,
                status: "blocked",
                packageURL: nil,
                outputURL: outputURL.standardizedFileURL,
                message: "Open a package before exporting browser bookmarks."
            )
            return
        }

        browserBookmarkExportState = .running

        do {
            let summary = try await runtime.exportBrowserBookmarks(
                package.url,
                outputURL.standardizedFileURL
            )
            browserBookmarkExportState = .succeeded(summary)
            recordAudit(
                operation: .browserBookmarkExport,
                status: "success",
                packageURL: summary.packageURL,
                outputURL: summary.outputURL,
                message: "Exported reviewable browser bookmark HTML handoff.",
                metrics: [
                    "browserSections": summary.browserSectionCount,
                    "bookmarksExported": summary.exportedBookmarkCount,
                    "duplicatesSkipped": summary.skippedDuplicateCount,
                    "invalidURLsSkipped": summary.skippedInvalidCount,
                    "unavailableSourcesSkipped": summary.skippedUnavailableSourceCount
                ]
            )
        } catch {
            browserBookmarkExportState = .failed(error.readableMessage)
            recordAudit(
                operation: .browserBookmarkExport,
                status: "failed",
                packageURL: package.url,
                outputURL: outputURL.standardizedFileURL,
                message: error.readableMessage
            )
        }
    }

    func planApplyForCurrentPackage() async {
        guard case let .succeeded(package) = packageState else {
            applyPlanState = .failed("Open a package before planning apply.")
            return
        }

        applyPlanState = .running
        confirmedApplyState = .idle

        do {
            let summary = try await runtime.planApplyPackage(package.url)
            applyPlanState = .succeeded(summary)
            recordAudit(
                operation: .dryRunApply,
                status: "success",
                packageURL: summary.packageURL,
                message: "Previewed non-mutating apply plan.",
                metrics: [
                    "actions": summary.actionCount,
                    "install": summary.installCount,
                    "configure": summary.configureCount,
                    "skip": summary.skipCount,
                    "blocked": summary.blockedCount,
                    "requiresUserAction": summary.userActionCount
                ]
            )
        } catch {
            applyPlanState = .failed(error.readableMessage)
            recordAudit(
                operation: .dryRunApply,
                status: "failed",
                packageURL: package.url,
                message: error.readableMessage
            )
        }
    }

    func confirmedApplyForCurrentPackage() async {
        guard case let .succeeded(package) = packageState else {
            confirmedApplyState = .failed("Open a package before confirmed apply.")
            recordAudit(
                operation: .confirmedApply,
                status: "blocked",
                packageURL: nil,
                message: "Open a package before confirmed apply."
            )
            return
        }
        guard case let .succeeded(plan) = applyPlanState, plan.packageURL == package.url else {
            confirmedApplyState = .failed("Run a dry run before confirmed apply.")
            recordAudit(
                operation: .confirmedApply,
                status: "blocked",
                packageURL: package.url,
                message: "Run a dry run before confirmed apply."
            )
            return
        }

        confirmedApplyState = .running

        do {
            let summary = try await runtime.confirmedApplyPackage(package.url)
            confirmedApplyState = .succeeded(summary)
            recordAudit(
                operation: .confirmedApply,
                status: summary.failedCount > 0 ? "warning" : "success",
                packageURL: summary.packageURL,
                backupURL: summary.backupURL,
                message: "Ran backed-up Finder-safe confirmed apply.",
                metrics: [
                    "results": summary.resultCount,
                    "applied": summary.appliedCount,
                    "warnings": summary.warningCount,
                    "skipped": summary.skippedCount,
                    "failed": summary.failedCount
                ]
            )
        } catch {
            confirmedApplyState = .failed(error.readableMessage)
            recordAudit(
                operation: .confirmedApply,
                status: "failed",
                packageURL: package.url,
                message: error.readableMessage
            )
        }
    }

    func compareCurrentPackage() async {
        guard case let .succeeded(package) = packageState else {
            compareState = .failed("Open a package before comparing.")
            return
        }

        compareState = .running

        do {
            compareState = .succeeded(try await runtime.comparePackage(package.url))
        } catch {
            compareState = .failed(error.readableMessage)
        }
    }

    func refreshDiagnostics() async {
        diagnosticsState = .running

        do {
            let capabilities = try await runtime.detectCapabilities()
            diagnosticsState = .succeeded(AppDiagnosticsSummary(capabilities: capabilities))
        } catch {
            diagnosticsState = .failed(error.readableMessage)
        }
    }

    func exportAuditLog(to outputURL: URL) {
        guard !auditLog.isEmpty else {
            auditExportState = .failed("No audit entries to export.")
            return
        }

        auditExportState = .running

        do {
            auditExportState = .succeeded(try AppAuditLogExporter().export(
                entries: auditLog,
                to: outputURL.standardizedFileURL
            ))
        } catch {
            auditExportState = .failed(error.readableMessage)
        }
    }

    private func recordAudit(
        operation: AppAuditOperation,
        status: String,
        packageURL: URL?,
        outputURL: URL? = nil,
        backupURL: URL? = nil,
        message: String,
        metrics: [String: Int] = [:]
    ) {
        auditLog.insert(AppAuditLogEntry(
            operation: operation,
            status: status,
            packageURL: packageURL,
            outputURL: outputURL,
            backupURL: backupURL,
            message: message,
            metrics: metrics
        ), at: 0)
        auditLog = Array(auditLog.prefix(50))
    }
}

enum AppCommandState<Value: Equatable>: Equatable {
    case idle
    case running
    case succeeded(Value)
    case failed(String)

    var isRunning: Bool {
        if case .running = self {
            return true
        }
        return false
    }
}

struct AppRuntime: Sendable {
    var createSnapshot: @Sendable (URL) async throws -> AppSnapshotSummary
    var openPackage: @Sendable (URL) async throws -> AppPackageSummary
    var comparePackage: @Sendable (URL) async throws -> AppCompareSummary
    var planApplyPackage: @Sendable (URL) async throws -> AppApplyPlanSummary
    var confirmedApplyPackage: @Sendable (URL) async throws -> AppConfirmedApplySummary
    var exportBrowserBookmarks: @Sendable (URL, URL) async throws -> AppBrowserBookmarkExportSummary
    var detectCapabilities: @Sendable () async throws -> MacCapabilities

    init(
        createSnapshot: @escaping @Sendable (URL) async throws -> AppSnapshotSummary,
        openPackage: @escaping @Sendable (URL) async throws -> AppPackageSummary,
        comparePackage: @escaping @Sendable (URL) async throws -> AppCompareSummary,
        planApplyPackage: @escaping @Sendable (URL) async throws -> AppApplyPlanSummary,
        confirmedApplyPackage: @escaping @Sendable (URL) async throws -> AppConfirmedApplySummary,
        exportBrowserBookmarks: @escaping @Sendable (URL, URL) async throws -> AppBrowserBookmarkExportSummary,
        detectCapabilities: @escaping @Sendable () async throws -> MacCapabilities
    ) {
        self.createSnapshot = createSnapshot
        self.openPackage = openPackage
        self.comparePackage = comparePackage
        self.planApplyPackage = planApplyPackage
        self.confirmedApplyPackage = confirmedApplyPackage
        self.exportBrowserBookmarks = exportBrowserBookmarks
        self.detectCapabilities = detectCapabilities
    }

    static let live = AppRuntime(
        createSnapshot: { outputURL in
            let result = try await MimicrySnapshotBuilder().writeSnapshot(to: outputURL)
            return AppSnapshotSummary(package: result.package)
        },
        openPackage: { packageURL in
            let package = try MimicryPackageStore().read(from: packageURL)
            return AppPackageSummary(package: package)
        },
        comparePackage: { packageURL in
            let package = try MimicryPackageStore().read(from: packageURL)
            let currentSnapshot = try await MimicrySnapshotBuilder().buildSnapshot().snapshot
            let report = SnapshotDiffEngine().diff(reference: package.snapshot, current: currentSnapshot)
            return AppCompareSummary(packageURL: package.url, report: report)
        },
        planApplyPackage: { packageURL in
            let package = try MimicryPackageStore().read(from: packageURL)
            let currentSnapshot = try await MimicrySnapshotBuilder().buildSnapshot().snapshot
            let plan = SnapshotApplyPlanner().plan(reference: package.snapshot, current: currentSnapshot)
            return AppApplyPlanSummary(packageURL: package.url, plan: plan)
        },
        confirmedApplyPackage: { packageURL in
            let package = try MimicryPackageStore().read(from: packageURL)
            let currentSnapshot = try await MimicrySnapshotBuilder().buildSnapshot().snapshot
            let result = try await FinderPreferenceApplyExecutor().apply(
                reference: package.snapshot,
                current: currentSnapshot
            )
            return AppConfirmedApplySummary(packageURL: package.url, summary: result)
        },
        exportBrowserBookmarks: { packageURL, outputURL in
            let package = try MimicryPackageStore().read(from: packageURL)
            let result = try BrowserBookmarkImportExporter().export(snapshot: package.snapshot, to: outputURL)
            return AppBrowserBookmarkExportSummary(packageURL: package.url, result: result)
        },
        detectCapabilities: {
            await MacCapabilitiesDetector().detect()
        }
    )
}

struct AppSnapshotSummary: Equatable, Sendable {
    var url: URL
    var sectionCount: Int
    var itemCount: Int
    var warningCount: Int
    var createdAt: Date
    var source: String

    init(
        url: URL,
        sectionCount: Int,
        itemCount: Int,
        warningCount: Int,
        createdAt: Date,
        source: String
    ) {
        self.url = url
        self.sectionCount = sectionCount
        self.itemCount = itemCount
        self.warningCount = warningCount
        self.createdAt = createdAt
        self.source = source
    }

    init(package: MimicryPackage) {
        let snapshot = package.snapshot
        self.init(
            url: package.url,
            sectionCount: snapshot.sections.count,
            itemCount: snapshot.sections.reduce(0) { $0 + $1.items.count },
            warningCount: snapshot.sections.reduce(0) { $0 + $1.warnings.count },
            createdAt: package.manifest.createdAt,
            source: "\(snapshot.source.hostname) (\(snapshot.source.username))"
        )
    }
}

struct AppPackageSummary: Equatable, Sendable {
    var url: URL
    var packageName: String
    var createdAt: Date
    var source: String
    var macOSVersion: String
    var architecture: String
    var sectionCount: Int
    var itemCount: Int
    var warningCount: Int
    var safeCount: Int
    var reviewCount: Int
    var excludedCount: Int
    var unsupportedCount: Int
    var compatibility: AppCompatibilitySummary
    var sections: [PackageSectionSummary]

    init(package: MimicryPackage) {
        let snapshot = package.snapshot
        let items = snapshot.sections.flatMap(\.items)
        let reviewClassifications: Set<ConfigurationClassification> = [
            .potentiallySensitive,
            .userMustReview,
            .machineSpecific,
            .hardwareSpecific,
            .managed
        ]

        url = package.url
        packageName = package.url.lastPathComponent
        createdAt = package.manifest.createdAt
        source = "\(snapshot.source.hostname) (\(snapshot.source.username))"
        macOSVersion = snapshot.source.macOSVersion
        architecture = snapshot.source.architecture
        sectionCount = snapshot.sections.count
        itemCount = items.count
        warningCount = snapshot.sections.reduce(0) { $0 + $1.warnings.count }
        safeCount = items.filter { $0.classification == .safeConfiguration }.count
        reviewCount = items.filter { reviewClassifications.contains($0.classification) }.count
        excludedCount = items.filter { $0.classification == .excluded }.count
        unsupportedCount = items.filter { $0.classification == .unsupported }.count
        compatibility = AppCompatibilitySummary(items: items)
        sections = snapshot.sections.map(PackageSectionSummary.init(section:))
    }
}

struct PackageSectionSummary: Equatable, Sendable, Identifiable {
    var id: String { identifier }
    var identifier: String
    var name: String
    var itemCount: Int
    var warningCount: Int
    var items: [PackageItemSummary]
    var warnings: [PackageWarningSummary]

    init(
        identifier: String,
        name: String,
        itemCount: Int,
        warningCount: Int,
        items: [PackageItemSummary] = [],
        warnings: [PackageWarningSummary] = []
    ) {
        self.identifier = identifier
        self.name = name
        self.itemCount = itemCount
        self.warningCount = warningCount
        self.items = items
        self.warnings = warnings
    }

    init(section: SnapshotSection) {
        self.init(
            identifier: section.identifier,
            name: section.displayName,
            itemCount: section.items.count,
            warningCount: section.warnings.count,
            items: section.items.map { PackageItemSummary(item: $0, sectionIdentifier: section.identifier) },
            warnings: section.warnings.map(PackageWarningSummary.init(warning:))
        )
    }

    var homebrewItemGroups: [PackageItemGroupSummary] {
        guard identifier == "homebrew" else {
            return []
        }

        return [
            PackageItemGroupSummary(
                title: "Homebrew",
                systemImage: "shippingbox",
                items: items.filter { !$0.key.isHomebrewChildItem }
            ),
            PackageItemGroupSummary(
                title: "Taps",
                systemImage: "drop",
                items: items.filter { $0.key.hasPrefix("homebrew.tap.") }
            ),
            PackageItemGroupSummary(
                title: "Formulae",
                systemImage: "terminal",
                items: items.filter { $0.key.hasPrefix("homebrew.formula.") }
            ),
            PackageItemGroupSummary(
                title: "Casks",
                systemImage: "app.dashed",
                items: items.filter { $0.key.hasPrefix("homebrew.cask.") }
            )
        ].filter { !$0.items.isEmpty }
    }
}

struct PackageItemGroupSummary: Equatable, Sendable, Identifiable {
    var id: String { title }
    var title: String
    var systemImage: String
    var items: [PackageItemSummary]
}

struct PackageItemSummary: Equatable, Sendable, Identifiable {
    var id: String { key }
    var key: String
    var value: String
    var classification: String
    var applicability: String
    var isInformationalOnly: Bool

    init(item: SnapshotItem, sectionIdentifier: String = "") {
        key = item.key
        value = item.value.renderedDescription
        classification = item.classification.rawValue.readableIdentifier
        applicability = item.applicability.rawValue.readableIdentifier
        isInformationalOnly = sectionIdentifier == "environment"
    }
}

private extension String {
    var isHomebrewChildItem: Bool {
        hasPrefix("homebrew.tap.")
            || hasPrefix("homebrew.formula.")
            || hasPrefix("homebrew.cask.")
    }
}

struct PackageWarningSummary: Equatable, Sendable, Identifiable {
    var id: String { code }
    var code: String
    var message: String

    init(warning: SnapshotWarning) {
        code = warning.code
        message = warning.message
    }
}

struct AppCompareSummary: Equatable, Sendable {
    var packageURL: URL
    var referenceSource: String
    var currentSource: String
    var sectionCount: Int
    var itemCount: Int
    var matchingCount: Int
    var changedCount: Int
    var missingCount: Int
    var currentOnlyCount: Int
    var skippedCount: Int
    var blockedCount: Int
    var sections: [CompareSectionSummary]

    init(packageURL: URL, report: SnapshotDiffReport) {
        self.packageURL = packageURL
        referenceSource = "\(report.referenceSource.hostname) (\(report.referenceSource.username))"
        currentSource = "\(report.currentSource.hostname) (\(report.currentSource.username))"
        sectionCount = report.sections.count
        itemCount = report.itemCount
        matchingCount = report.count(.matching)
        changedCount = report.count(.changed)
        missingCount = report.count(.missing)
        currentOnlyCount = report.count(.currentOnly)
        skippedCount = report.count(.skipped)
        blockedCount = report.count(.unsupported)
        sections = report.sections.map(CompareSectionSummary.init(section:))
    }
}

struct CompareSectionSummary: Equatable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var itemCount: Int
    var matchingCount: Int
    var changedCount: Int
    var missingCount: Int
    var currentOnlyCount: Int
    var skippedCount: Int
    var blockedCount: Int
    var warningCount: Int

    init(section: SnapshotSectionDiff) {
        name = section.displayName
        itemCount = section.items.count
        matchingCount = section.count(.matching)
        changedCount = section.count(.changed)
        missingCount = section.count(.missing)
        currentOnlyCount = section.count(.currentOnly)
        skippedCount = section.count(.skipped)
        blockedCount = section.count(.unsupported)
        warningCount = section.referenceWarnings.count + section.currentWarnings.count
    }
}

struct AppApplyPlanSummary: Equatable, Sendable {
    var packageURL: URL
    var referenceSource: String
    var currentSource: String
    var actionCount: Int
    var installCount: Int
    var configureCount: Int
    var skipCount: Int
    var blockedCount: Int
    var userActionCount: Int
    var compatibility: AppCompatibilitySummary
    var groups: [ApplyActionGroupSummary]

    init(packageURL: URL, plan: SnapshotApplyPlan) {
        self.packageURL = packageURL
        referenceSource = "\(plan.diff.referenceSource.hostname) (\(plan.diff.referenceSource.username))"
        currentSource = "\(plan.diff.currentSource.hostname) (\(plan.diff.currentSource.username))"
        actionCount = plan.actions.count
        installCount = plan.count(.install)
        configureCount = plan.count(.configure)
        skipCount = plan.count(.skip)
        blockedCount = plan.count(.blocked)
        userActionCount = plan.count(.requiresUserAction)
        compatibility = AppCompatibilitySummary(diffItems: plan.diff.sections.flatMap(\.items))
        groups = PlannedActionKind.displayOrder.compactMap { kind in
            let actions = plan.actions.filter { $0.kind == kind }
            guard !actions.isEmpty else {
                return nil
            }

            return ApplyActionGroupSummary(kind: kind, actions: actions)
        }
    }
}

struct ApplyActionGroupSummary: Equatable, Sendable, Identifiable {
    var id: String { title }
    var title: String
    var actionCount: Int
    var actions: [AppPlannedActionSummary]

    init(kind: PlannedActionKind, actions: [PlannedAction]) {
        title = kind.groupTitle
        actionCount = actions.count
        self.actions = actions.map(AppPlannedActionSummary.init(action:))
    }
}

struct AppPlannedActionSummary: Equatable, Sendable, Identifiable {
    var id: UUID
    var provider: String
    var detail: String
    var requiresElevation: Bool

    init(action: PlannedAction) {
        id = action.id
        provider = action.providerIdentifier
        detail = action.summary
        requiresElevation = action.requiresElevation
    }
}

struct AppBrowserBookmarkExportSummary: Equatable, Sendable {
    var packageURL: URL
    var outputURL: URL
    var browserSectionCount: Int
    var exportedBookmarkCount: Int
    var skippedDuplicateCount: Int
    var skippedInvalidCount: Int
    var skippedUnavailableSourceCount: Int

    init(packageURL: URL, result: BrowserBookmarkImportResult) {
        self.packageURL = packageURL
        outputURL = result.outputURL
        browserSectionCount = result.summary.browserSectionCount
        exportedBookmarkCount = result.summary.exportedBookmarkCount
        skippedDuplicateCount = result.summary.skippedDuplicateCount
        skippedInvalidCount = result.summary.skippedInvalidCount
        skippedUnavailableSourceCount = result.summary.skippedUnavailableSourceCount
    }
}

struct AppConfirmedApplySummary: Equatable, Sendable {
    var packageURL: URL
    var backupURL: URL?
    var resultCount: Int
    var appliedCount: Int
    var warningCount: Int
    var skippedCount: Int
    var failedCount: Int
    var results: [AppApplyResultSummary]

    init(packageURL: URL, summary: FinderPreferenceApplySummary) {
        self.packageURL = packageURL
        backupURL = summary.backupURL
        resultCount = summary.results.count
        appliedCount = summary.results.filter { $0.status == .success }.count
        warningCount = summary.results.filter { $0.status == .warning }.count
        skippedCount = summary.results.filter { $0.status == .skipped || $0.status == .unsupported }.count
        failedCount = summary.results.filter { $0.status == .fatal || $0.status == .blocked }.count
        results = summary.results.map(AppApplyResultSummary.init(result:))
    }
}

struct AppApplyResultSummary: Equatable, Sendable, Identifiable {
    var id: UUID
    var status: String
    var message: String

    init(result: ApplyResult) {
        id = result.actionID
        status = result.status.rawValue
        message = result.message
    }
}

struct AppCompatibilitySummary: Equatable, Sendable {
    var managedCount: Int
    var machineSpecificCount: Int
    var hardwareSpecificCount: Int
    var userSpecificCount: Int
    var unsupportedCount: Int

    init(
        managedCount: Int = 0,
        machineSpecificCount: Int = 0,
        hardwareSpecificCount: Int = 0,
        userSpecificCount: Int = 0,
        unsupportedCount: Int = 0
    ) {
        self.managedCount = managedCount
        self.machineSpecificCount = machineSpecificCount
        self.hardwareSpecificCount = hardwareSpecificCount
        self.userSpecificCount = userSpecificCount
        self.unsupportedCount = unsupportedCount
    }

    init(items: [SnapshotItem]) {
        self.init(
            managedCount: items.filter(\.isManaged).count,
            machineSpecificCount: items.filter(\.isMachineSpecific).count,
            hardwareSpecificCount: items.filter(\.isHardwareSpecific).count,
            userSpecificCount: items.filter(\.isUserSpecific).count,
            unsupportedCount: items.filter { $0.classification == .unsupported }.count
        )
    }

    init(diffItems: [SnapshotItemDiff]) {
        let relevantItems = diffItems.filter { item in
            item.status == .changed || item.status == .missing || item.status == .unsupported
        }
        self.init(
            managedCount: relevantItems.filter(\.isManaged).count,
            machineSpecificCount: relevantItems.filter(\.isMachineSpecific).count,
            hardwareSpecificCount: relevantItems.filter(\.isHardwareSpecific).count,
            userSpecificCount: relevantItems.filter(\.isUserSpecific).count,
            unsupportedCount: relevantItems.filter { $0.classification == .unsupported }.count
        )
    }

    var constrainedCount: Int {
        managedCount + machineSpecificCount + hardwareSpecificCount + userSpecificCount + unsupportedCount
    }

    var hasConstrainedItems: Bool {
        constrainedCount > 0
    }
}

enum AppAuditOperation: String, Codable, Equatable, Sendable {
    case snapshot
    case openPackage
    case dryRunApply
    case confirmedApply
    case browserBookmarkExport

    var displayName: String {
        switch self {
        case .snapshot:
            "Snapshot"
        case .openPackage:
            "Open Package"
        case .dryRunApply:
            "Dry Run"
        case .confirmedApply:
            "Confirmed Apply"
        case .browserBookmarkExport:
            "Browser Handoff"
        }
    }
}

struct AppAuditLogEntry: Codable, Equatable, Sendable, Identifiable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var operation: AppAuditOperation
    var status: String
    var packageURL: URL?
    var outputURL: URL?
    var backupURL: URL?
    var message: String
    var metrics: [String: Int]
}

struct AppAuditExportSummary: Equatable, Sendable {
    var outputURL: URL
    var entryCount: Int
}

struct AppAuditLogExporter {
    func export(entries: [AppAuditLogEntry], to outputURL: URL) throws -> AppAuditExportSummary {
        let document = AppAuditLogDocument(exportedAt: Date(), entries: entries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)
        return AppAuditExportSummary(outputURL: outputURL, entryCount: entries.count)
    }
}

private struct AppAuditLogDocument: Codable {
    var schemaVersion = 1
    var exportedAt: Date
    var entries: [AppAuditLogEntry]
}

struct AppDiagnosticsSummary: Equatable, Sendable {
    var host: String
    var macOSVersion: String
    var architecture: String
    var managementDetail: String
    var rows: [DiagnosticRow]

    init(capabilities: MacCapabilities) {
        host = capabilities.hostname
        macOSVersion = capabilities.macOSVersion
        architecture = capabilities.architecture.rawValue
        managementDetail = capabilities.managementState.managementDetail
        rows = [
            DiagnosticRow(label: "Command Line Tools", value: capabilities.hasCommandLineTools.availabilityLabel),
            DiagnosticRow(label: "Homebrew", value: capabilities.homebrew.isInstalled.availabilityLabel),
            DiagnosticRow(label: "mas", value: capabilities.hasMAS.availabilityLabel),
            DiagnosticRow(label: "FileVault", value: capabilities.fileVaultState.displayLabel),
            DiagnosticRow(label: "SIP", value: capabilities.sipState.displayLabel),
            DiagnosticRow(label: "iCloud", value: capabilities.iCloudState.displayLabel),
            DiagnosticRow(label: "App Store", value: capabilities.appStoreState.displayLabel),
            DiagnosticRow(label: "Management", value: capabilities.managementState.displayLabel)
        ]
    }
}

private extension SnapshotItem {
    var isManaged: Bool {
        classification == .managed || applicability == .managedDeviceOnly
    }

    var isMachineSpecific: Bool {
        classification == .machineSpecific || applicability == .machineSpecific
    }

    var isHardwareSpecific: Bool {
        classification == .hardwareSpecific || applicability.isHardwareSpecific
    }

    var isUserSpecific: Bool {
        applicability == .userSpecific
    }
}

private extension SnapshotItemDiff {
    var isManaged: Bool {
        classification == .managed || applicability == .managedDeviceOnly
    }

    var isMachineSpecific: Bool {
        classification == .machineSpecific || applicability == .machineSpecific
    }

    var isHardwareSpecific: Bool {
        classification == .hardwareSpecific || applicability.isHardwareSpecific
    }

    var isUserSpecific: Bool {
        applicability == .userSpecific
    }
}

private extension ConfigurationApplicability {
    var isHardwareSpecific: Bool {
        switch self {
        case .appleSiliconOnly, .intelOnly, .laptopOnly, .desktopOnly, .externalDisplayDependent, .externalInputDeviceDependent:
            true
        case .universal, .userSpecific, .machineSpecific, .managedDeviceOnly:
            false
        }
    }
}

private extension SnapshotSectionDiff {
    func count(_ status: SnapshotDiffStatus) -> Int {
        items.filter { $0.status == status }.count
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

    var groupTitle: String {
        switch self {
        case .install:
            "INSTALL"
        case .configure:
            "CONFIGURE"
        case .skip:
            "SKIP"
        case .blocked:
            "BLOCKED"
        case .requiresUserAction:
            "REQUIRES USER ACTION"
        }
    }
}

struct DiagnosticRow: Equatable, Sendable, Identifiable {
    var id: String { label }
    var label: String
    var value: String
}

struct RecentPackage: Equatable, Identifiable {
    var id: String { url.path }
    var url: URL
    var name: String
    var path: String
    var lastOpenedAt: Date?

    init(url: URL, lastOpenedAt: Date? = nil) {
        self.url = url
        name = url.lastPathComponent
        path = url.deletingLastPathComponent().path
        self.lastOpenedAt = lastOpenedAt
    }
}

struct PackageHistoryStore {
    private let loadPackages: () -> [RecentPackage]
    private let recordPackage: (URL) -> [RecentPackage]

    init(
        load: @escaping () -> [RecentPackage],
        record: @escaping (URL) -> [RecentPackage]
    ) {
        loadPackages = load
        recordPackage = record
    }

    func load() -> [RecentPackage] {
        loadPackages()
    }

    func record(_ url: URL) -> [RecentPackage] {
        recordPackage(url)
    }

    static func userDefaults(_ defaults: UserDefaults = .standard) -> PackageHistoryStore {
        let key = "recentMimicryPackagePaths"

        func packages(from paths: [String]) -> [RecentPackage] {
            paths.map { path in
                let url = URL(fileURLWithPath: path)
                let modificationDate = try? FileManager.default
                    .attributesOfItem(atPath: path)[.modificationDate] as? Date
                return RecentPackage(url: url, lastOpenedAt: modificationDate)
            }
        }

        return PackageHistoryStore {
            packages(from: defaults.stringArray(forKey: key) ?? [])
        } record: { url in
            let path = url.standardizedFileURL.path
            var paths = defaults.stringArray(forKey: key) ?? []
            paths.removeAll { $0 == path }
            paths.insert(path, at: 0)
            paths = Array(paths.prefix(8))
            defaults.set(paths, forKey: key)
            return packages(from: paths)
        }
    }
}

private extension Bool {
    var availabilityLabel: String {
        self ? "Available" : "Unavailable"
    }
}

private extension CapabilityState {
    var displayLabel: String {
        switch self {
        case .available:
            "Available"
        case .unavailable:
            "Unavailable"
        case .enabled:
            "Enabled"
        case .disabled:
            "Disabled"
        case .managed:
            "Managed"
        case .requiresUserAction:
            "Requires user action"
        case .unsupported:
            "Unsupported"
        case .unknown:
            "Unknown"
        }
    }

    var managementDetail: String {
        switch self {
        case .managed:
            "This Mac appears managed; some settings may be controlled by profiles or MDM."
        case .requiresUserAction:
            "Management state needs user review before applying managed or protected settings."
        case .unavailable:
            "No local management signals were available."
        case .unknown:
            "Management state could not be confirmed from local diagnostics."
        case .available, .enabled:
            "Management checks are available; review package managed-setting counts before applying."
        case .disabled:
            "Management checks appear disabled on this Mac."
        case .unsupported:
            "Management checks are unsupported on this Mac."
        }
    }
}

private extension Error {
    var readableMessage: String {
        let message = localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? String(describing: self) : message
    }
}

private extension String {
    var readableIdentifier: String {
        var words: [String] = []
        var current = ""

        for character in self {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = String(character)
            } else if character == "-" || character == "_" {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty {
            words.append(current)
        }

        return words
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
