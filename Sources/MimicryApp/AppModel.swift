import Combine
import Foundation
import MimicryCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshotState: AppCommandState<AppSnapshotSummary> = .idle
    @Published private(set) var packageState: AppCommandState<AppPackageSummary> = .idle
    @Published private(set) var compareState: AppCommandState<AppCompareSummary> = .idle
    @Published private(set) var diagnosticsState: AppCommandState<AppDiagnosticsSummary> = .idle
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
            do {
                packageState = .succeeded(try await runtime.openPackage(summary.url))
            } catch {
                packageState = .failed(error.readableMessage)
            }
            recentPackages = historyStore.record(summary.url)
        } catch {
            snapshotState = .failed(error.readableMessage)
        }
    }

    func openPackage(at packageURL: URL) async {
        packageState = .running
        compareState = .idle

        do {
            let summary = try await runtime.openPackage(packageURL.standardizedFileURL)
            packageState = .succeeded(summary)
            recentPackages = historyStore.record(summary.url)
        } catch {
            packageState = .failed(error.readableMessage)
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
    var detectCapabilities: @Sendable () async throws -> MacCapabilities

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
        sections = snapshot.sections.map(PackageSectionSummary.init(section:))
    }
}

struct PackageSectionSummary: Equatable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var itemCount: Int
    var warningCount: Int

    init(name: String, itemCount: Int, warningCount: Int) {
        self.name = name
        self.itemCount = itemCount
        self.warningCount = warningCount
    }

    init(section: SnapshotSection) {
        self.init(
            name: section.displayName,
            itemCount: section.items.count,
            warningCount: section.warnings.count
        )
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

struct AppDiagnosticsSummary: Equatable, Sendable {
    var host: String
    var macOSVersion: String
    var architecture: String
    var rows: [DiagnosticRow]

    init(capabilities: MacCapabilities) {
        host = capabilities.hostname
        macOSVersion = capabilities.macOSVersion
        architecture = capabilities.architecture.rawValue
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

private extension SnapshotSectionDiff {
    func count(_ status: SnapshotDiffStatus) -> Int {
        items.filter { $0.status == status }.count
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
}

private extension Error {
    var readableMessage: String {
        let message = localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? String(describing: self) : message
    }
}
