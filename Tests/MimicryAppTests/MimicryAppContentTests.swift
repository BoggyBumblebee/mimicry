import AppKit
import MimicryCore
import SwiftUI
@testable import Mimicry
import XCTest

@MainActor
final class MimicryAppContentTests: XCTestCase {
    func testRootViewCanBeHosted() {
        let host = NSHostingView(rootView: RootView())
        host.frame = CGRect(x: 0, y: 0, width: 980, height: 660)

        host.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(host.fittingSize.width, 0)
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testDashboardDetailCanBeHosted() {
        let host = NSHostingView(rootView: DetailView(section: .dashboard, model: Self.makeModel()))
        host.frame = CGRect(x: 0, y: 0, width: 900, height: 640)

        host.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(host.fittingSize.width, 0)
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testEverySectionDetailCanBeHosted() {
        for section in AppSection.allCases {
            let host = NSHostingView(rootView: DetailView(section: section, model: Self.makeModel()))
            host.frame = CGRect(x: 0, y: 0, width: 900, height: 640)

            host.layoutSubtreeIfNeeded()

            XCTAssertGreaterThan(host.fittingSize.width, 0, section.title)
            XCTAssertGreaterThan(host.fittingSize.height, 0, section.title)
        }
    }

    func testSettingsCanBeHosted() {
        let host = NSHostingView(rootView: SettingsView())
        host.frame = CGRect(x: 0, y: 0, width: 460, height: 220)

        host.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(host.fittingSize.width, 0)
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testSectionsCoverPrimaryWorkflows() {
        XCTAssertEqual(AppSection.allCases.map(\.title), [
            "Dashboard",
            "Snapshot",
            "Apply",
            "Compare",
            "History",
            "Diagnostics"
        ])
        XCTAssertTrue(AppSection.allCases.allSatisfy { !$0.subtitle.isEmpty })
        XCTAssertTrue(AppSection.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }

    func testDashboardSummariesKeepSafetyBoundariesVisible() {
        let summaries = CapabilitySummary.current

        XCTAssertEqual(summaries.map(\.title), ["Providers", "Apply", "Browsers", "Quality"])
        XCTAssertTrue(summaries.contains { $0.detail.contains("Finder boolean and string preferences") })
        XCTAssertTrue(summaries.contains { $0.detail.contains("HTML import artifact") })
        XCTAssertTrue(summaries.contains { $0.detail.contains("zero open Sonar issues") })
    }

    func testWorkflowStepsMatchTrustedLoop() {
        XCTAssertEqual(WorkflowStep.current.map(\.title), [
            "Capture",
            "Inspect",
            "Compare",
            "Dry Run",
            "Apply"
        ])
        XCTAssertTrue(WorkflowStep.current.contains { $0.detail.contains("explicit confirmation") })
    }

    func testCompareGroupsMatchDiffStatuses() {
        XCTAssertEqual(DiffGroup.current.map(\.title), [
            "Matching",
            "Changed",
            "Missing",
            "Current Only",
            "Skipped",
            "Blocked"
        ])
    }

    func testSnapshotActionRecordsPackageHistory() async {
        let model = Self.makeModel(
            runtime: AppRuntime(
                createSnapshot: { url in
                    AppSnapshotSummary(
                        url: url,
                        sectionCount: 9,
                        itemCount: 42,
                        warningCount: 2,
                        createdAt: Date(timeIntervalSince1970: 1_788_000_000),
                        source: "source-mac (cmb)"
                    )
                },
                openPackage: { url in
                    AppPackageSummary(package: Self.samplePackage(url: url))
                },
                comparePackage: { url in
                    Self.sampleCompareSummary(url: url)
                },
                detectCapabilities: { Self.sampleCapabilities }
            ),
            historyStore: PackageHistoryStore(
                load: { [] },
                record: { [RecentPackage(url: $0)] }
            )
        )

        await model.createSnapshot(to: URL(fileURLWithPath: "/tmp/gui-snapshot.mimicry"))

        XCTAssertEqual(model.recentPackages.map(\.name), ["gui-snapshot.mimicry"])
        XCTAssertEqual(model.snapshotState, .succeeded(AppSnapshotSummary(
            url: URL(fileURLWithPath: "/tmp/gui-snapshot.mimicry"),
            sectionCount: 9,
            itemCount: 42,
            warningCount: 2,
            createdAt: Date(timeIntervalSince1970: 1_788_000_000),
            source: "source-mac (cmb)"
        )))
        XCTAssertEqual(
            model.packageState,
            .succeeded(AppPackageSummary(package: Self.samplePackage(url: URL(fileURLWithPath: "/tmp/gui-snapshot.mimicry"))))
        )
    }

    func testSnapshotActionReportsFailure() async {
        let model = Self.makeModel(runtime: AppRuntime(
            createSnapshot: { _ in throw AppTestError.snapshotFailed },
            openPackage: { _ in AppPackageSummary(package: Self.samplePackage()) },
            comparePackage: { _ in Self.sampleCompareSummary() },
            detectCapabilities: { Self.sampleCapabilities }
        ))

        await model.createSnapshot(to: URL(fileURLWithPath: "/tmp/gui-snapshot.mimicry"))

        XCTAssertEqual(model.snapshotState, .failed("Snapshot test failure"))
        XCTAssertTrue(model.recentPackages.isEmpty)
    }

    func testOpenPackageRecordsHistoryAndSummarizesContents() async {
        let model = Self.makeModel(
            runtime: AppRuntime(
                createSnapshot: { url in
                    AppSnapshotSummary(
                        url: url,
                        sectionCount: 0,
                        itemCount: 0,
                        warningCount: 0,
                        createdAt: Date(timeIntervalSince1970: 0),
                        source: "unused"
                    )
                },
                openPackage: { _ in AppPackageSummary(package: Self.samplePackage()) },
                comparePackage: { url in Self.sampleCompareSummary(url: url) },
                detectCapabilities: { Self.sampleCapabilities }
            ),
            historyStore: PackageHistoryStore(
                load: { [] },
                record: { [RecentPackage(url: $0)] }
            )
        )

        await model.openPackage(at: URL(fileURLWithPath: "/tmp/opened.mimicry"))

        let expected = AppPackageSummary(package: Self.samplePackage())
        XCTAssertEqual(model.packageState, .succeeded(expected))
        XCTAssertEqual(model.recentPackages.map(\.name), ["opened.mimicry"])
        XCTAssertEqual(expected.safeCount, 1)
        XCTAssertEqual(expected.reviewCount, 2)
        XCTAssertEqual(expected.excludedCount, 1)
        XCTAssertEqual(expected.unsupportedCount, 1)
        XCTAssertEqual(expected.sections.map(\.name), ["Environment", "Browser"])
    }

    func testOpenPackageReportsFailure() async {
        let model = Self.makeModel(runtime: AppRuntime(
            createSnapshot: { url in
                AppSnapshotSummary(
                    url: url,
                    sectionCount: 0,
                    itemCount: 0,
                    warningCount: 0,
                    createdAt: Date(timeIntervalSince1970: 0),
                    source: "unused"
                )
            },
            openPackage: { _ in throw AppTestError.packageFailed },
            comparePackage: { _ in Self.sampleCompareSummary() },
            detectCapabilities: { Self.sampleCapabilities }
        ))

        await model.openPackage(at: URL(fileURLWithPath: "/tmp/opened.mimicry"))

        XCTAssertEqual(model.packageState, .failed("Package test failure"))
        XCTAssertTrue(model.recentPackages.isEmpty)
    }

    func testCompareCurrentPackageRequiresOpenPackage() async {
        let model = Self.makeModel()

        await model.compareCurrentPackage()

        XCTAssertEqual(model.compareState, .failed("Open a package before comparing."))
    }

    func testCompareCurrentPackageSummarizesDiff() async {
        let model = Self.makeModel(
            runtime: AppRuntime(
                createSnapshot: { url in
                    AppSnapshotSummary(
                        url: url,
                        sectionCount: 0,
                        itemCount: 0,
                        warningCount: 0,
                        createdAt: Date(timeIntervalSince1970: 0),
                        source: "unused"
                    )
                },
                openPackage: { url in AppPackageSummary(package: Self.samplePackage(url: url)) },
                comparePackage: { url in Self.sampleCompareSummary(url: url) },
                detectCapabilities: { Self.sampleCapabilities }
            ),
            historyStore: PackageHistoryStore(
                load: { [] },
                record: { [RecentPackage(url: $0)] }
            )
        )

        await model.openPackage(at: URL(fileURLWithPath: "/tmp/opened.mimicry"))
        await model.compareCurrentPackage()

        let expected = Self.sampleCompareSummary()
        XCTAssertEqual(model.compareState, .succeeded(expected))
        XCTAssertEqual(expected.matchingCount, 2)
        XCTAssertEqual(expected.changedCount, 1)
        XCTAssertEqual(expected.missingCount, 0)
        XCTAssertEqual(expected.currentOnlyCount, 1)
        XCTAssertEqual(expected.skippedCount, 1)
        XCTAssertEqual(expected.blockedCount, 1)
        XCTAssertEqual(expected.sections.map(\.name), ["Browser", "Environment"])
    }

    func testCompareCurrentPackageReportsFailure() async {
        let model = Self.makeModel(runtime: AppRuntime(
            createSnapshot: { url in
                AppSnapshotSummary(
                    url: url,
                    sectionCount: 0,
                    itemCount: 0,
                    warningCount: 0,
                    createdAt: Date(timeIntervalSince1970: 0),
                    source: "unused"
                )
            },
            openPackage: { url in AppPackageSummary(package: Self.samplePackage(url: url)) },
            comparePackage: { _ in throw AppTestError.compareFailed },
            detectCapabilities: { Self.sampleCapabilities }
        ))

        await model.openPackage(at: URL(fileURLWithPath: "/tmp/opened.mimicry"))
        await model.compareCurrentPackage()

        XCTAssertEqual(model.compareState, .failed("Compare test failure"))
    }

    func testDiagnosticsRefreshSummarizesCapabilities() async {
        let model = Self.makeModel(runtime: AppRuntime(
            createSnapshot: { url in
                AppSnapshotSummary(
                    url: url,
                    sectionCount: 0,
                    itemCount: 0,
                    warningCount: 0,
                    createdAt: Date(timeIntervalSince1970: 0),
                    source: "unused"
                )
            },
            openPackage: { _ in AppPackageSummary(package: Self.samplePackage()) },
            comparePackage: { _ in Self.sampleCompareSummary() },
            detectCapabilities: { Self.sampleCapabilities }
        ))

        await model.refreshDiagnostics()

        let expected = AppDiagnosticsSummary(capabilities: Self.sampleCapabilities)
        XCTAssertEqual(model.diagnosticsState, .succeeded(expected))
        XCTAssertTrue(expected.rows.contains(DiagnosticRow(label: "Homebrew", value: "Available")))
        XCTAssertTrue(expected.rows.contains(DiagnosticRow(label: "Management", value: "Managed")))
    }

    func testHistoryStoreKeepsMostRecentPackageFirst() {
        let defaults = UserDefaults(suiteName: "MimicryAppContentTests.\(UUID().uuidString)")!
        let store = PackageHistoryStore.userDefaults(defaults)

        _ = store.record(URL(fileURLWithPath: "/tmp/first.mimicry"))
        _ = store.record(URL(fileURLWithPath: "/tmp/second.mimicry"))
        _ = store.record(URL(fileURLWithPath: "/tmp/first.mimicry"))

        XCTAssertEqual(store.load().map(\.name), ["first.mimicry", "second.mimicry"])
    }

    private static func makeModel(
        runtime: AppRuntime = AppRuntime(
            createSnapshot: { url in
                AppSnapshotSummary(
                    url: url,
                    sectionCount: 1,
                    itemCount: 1,
                    warningCount: 0,
                    createdAt: Date(timeIntervalSince1970: 0),
                    source: "preview"
                )
            },
            openPackage: { _ in AppPackageSummary(package: samplePackage()) },
            comparePackage: { url in sampleCompareSummary(url: url) },
            detectCapabilities: { sampleCapabilities }
        ),
        historyStore: PackageHistoryStore = PackageHistoryStore(load: { [] }, record: { [RecentPackage(url: $0)] })
    ) -> AppModel {
        AppModel(runtime: runtime, historyStore: historyStore)
    }

    nonisolated private static let sampleCapabilities = MacCapabilities(
        environment: MacEnvironment(
            macOSVersion: "15.5",
            architecture: .arm64,
            hardwareModel: "Mac16,1",
            hostname: "test-mac",
            username: "cmb"
        ),
        security: MacSecurityCapabilities(
            hasAdministratorPrivileges: true,
            fileVaultState: .enabled,
            sipState: .enabled
        ),
        tools: MacToolCapabilities(
            hasCommandLineTools: true,
            xcodeVersion: "17.0",
            homebrew: HomebrewCapability(
                isInstalled: true,
                prefix: "/opt/homebrew",
                version: "4.6.0",
                architecture: .arm64
            ),
            hasMAS: false
        ),
        services: MacServiceCapabilities(
            iCloudState: .requiresUserAction,
            appStoreState: .available,
            managementState: .managed
        )
    )

    nonisolated private static func samplePackage(
        url: URL = URL(fileURLWithPath: "/tmp/opened.mimicry")
    ) -> MimicryPackage {
        MimicryPackage(
            url: url,
            manifest: MimicryPackageManifest(createdAt: Date(timeIntervalSince1970: 1_788_000_100)),
            snapshot: MimicrySnapshot(
                mimicryVersion: "0.1.0",
                createdAt: Date(timeIntervalSince1970: 1_788_000_100),
                source: SnapshotSource(
                    macOSVersion: "15.5",
                    architecture: "arm64",
                    hardwareModel: "Mac16,1",
                    hostname: "source-mac",
                    username: "cmb"
                ),
                sections: [
                    SnapshotSection(
                        identifier: "environment",
                        displayName: "Environment",
                        items: [
                            SnapshotItem(key: "safe", value: .string("ok")),
                            SnapshotItem(key: "review", value: .string("check"), classification: .userMustReview),
                            SnapshotItem(key: "excluded", value: .string("redacted"), classification: .excluded)
                        ],
                        warnings: [SnapshotWarning(code: "environment.warning", message: "Review environment")]
                    ),
                    SnapshotSection(
                        identifier: "browser",
                        displayName: "Browser",
                        items: [
                            SnapshotItem(key: "managed", value: .string("managed"), classification: .managed),
                            SnapshotItem(key: "unsupported", value: .absent, classification: .unsupported)
                        ]
                    )
                ]
            )
        )
    }

    nonisolated private static func sampleCompareSummary(
        url: URL = URL(fileURLWithPath: "/tmp/opened.mimicry")
    ) -> AppCompareSummary {
        AppCompareSummary(
            packageURL: url,
            report: SnapshotDiffEngine().diff(
                reference: samplePackage(url: url).snapshot,
                current: sampleCurrentSnapshot()
            )
        )
    }

    nonisolated private static func sampleCurrentSnapshot() -> MimicrySnapshot {
        MimicrySnapshot(
            mimicryVersion: "0.1.0",
            source: SnapshotSource(
                macOSVersion: "15.5",
                architecture: "arm64",
                hardwareModel: "Mac16,1",
                hostname: "current-mac",
                username: "cmb"
            ),
            sections: [
                SnapshotSection(
                    identifier: "environment",
                    displayName: "Environment",
                    items: [
                        SnapshotItem(key: "safe", value: .string("ok")),
                        SnapshotItem(key: "review", value: .string("changed"), classification: .userMustReview),
                        SnapshotItem(key: "current-only", value: .string("local"))
                    ],
                    warnings: [SnapshotWarning(code: "environment.current-warning", message: "Current warning")]
                ),
                SnapshotSection(
                    identifier: "browser",
                    displayName: "Browser",
                    items: [
                        SnapshotItem(key: "managed", value: .string("managed"), classification: .managed)
                    ]
                )
            ]
        )
    }
}

private enum AppTestError: LocalizedError {
    case snapshotFailed
    case packageFailed
    case compareFailed

    var errorDescription: String? {
        switch self {
        case .snapshotFailed:
            "Snapshot test failure"
        case .packageFailed:
            "Package test failure"
        case .compareFailed:
            "Compare test failure"
        }
    }
}
