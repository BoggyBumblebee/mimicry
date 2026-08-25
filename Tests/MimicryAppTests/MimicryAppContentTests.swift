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

    func testDashboardProvidersExplainCapturedAreas() {
        let providers = ProviderSummary.current

        XCTAssertEqual(providers.map(\.title), [
            "Environment",
            "Homebrew",
            "App Store",
            "Finder",
            "Terminal",
            "iCloud",
            "Safari",
            "Chrome",
            "Firefox"
        ])
        XCTAssertTrue(providers.contains { $0.detail.contains("confirmed safe write path") })
        XCTAssertTrue(providers.contains { $0.detail.contains("browser import handoff") })
        XCTAssertFalse(providers.contains { $0.title == "Quality" })
    }

    func testHomebrewPackageItemsAreGroupedForReview() {
        let section = PackageSectionSummary(section: SnapshotSection(
            identifier: "homebrew",
            displayName: "Homebrew",
            items: [
                SnapshotItem(key: "homebrew.installed", value: .bool(true)),
                SnapshotItem(key: "homebrew.prefix", value: .string("/opt/homebrew"), classification: .machineSpecific),
                SnapshotItem(key: "homebrew.tap.homebrew/core", value: .string("homebrew/core")),
                SnapshotItem(key: "homebrew.formula.git", value: .object(["name": "git", "version": "2.51.0"])),
                SnapshotItem(key: "homebrew.cask.visual-studio-code", value: .object(["name": "visual-studio-code", "version": "1.102.3"]))
            ]
        ))

        XCTAssertEqual(section.homebrewItemGroups.map(\.title), ["Config", "Taps", "Formulae", "Casks"])
        XCTAssertEqual(section.homebrewItemGroups.map { $0.items.map(\.key) }, [
            ["homebrew.installed", "homebrew.prefix"],
            ["homebrew.tap.homebrew/core"],
            ["homebrew.formula.git"],
            ["homebrew.cask.visual-studio-code"]
        ])
    }

    func testWorkflowStepsMatchTrustedLoop() {
        XCTAssertEqual(WorkflowStep.current.map(\.title), [
            "Snapshot: Capture",
            "Snapshot: Inspect",
            "Compare",
            "Apply: Dry Run",
            "Apply: Confirm"
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
                planApplyPackage: { url in
                    Self.sampleApplyPlanSummary(url: url)
                },
                confirmedApplyPackage: { url in
                    Self.sampleConfirmedApplySummary(packageURL: url)
                },
                exportBrowserBookmarks: { packageURL, outputURL in
                    Self.sampleBrowserBookmarkExportSummary(packageURL: packageURL, outputURL: outputURL)
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
            planApplyPackage: { _ in Self.sampleApplyPlanSummary() },
            confirmedApplyPackage: { url in Self.sampleConfirmedApplySummary(packageURL: url) },
            exportBrowserBookmarks: { packageURL, outputURL in
                Self.sampleBrowserBookmarkExportSummary(packageURL: packageURL, outputURL: outputURL)
            },
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
                planApplyPackage: { url in Self.sampleApplyPlanSummary(url: url) },
                confirmedApplyPackage: { url in Self.sampleConfirmedApplySummary(packageURL: url) },
                exportBrowserBookmarks: { packageURL, outputURL in
                    Self.sampleBrowserBookmarkExportSummary(packageURL: packageURL, outputURL: outputURL)
                },
                detectCapabilities: { Self.sampleCapabilities }
            ),
            historyStore: PackageHistoryStore(
                load: { [] },
                record: { [RecentPackage(url: $0)] }
            )
        )

        await model.openPackage(at: URL(fileURLWithPath: "/tmp/opened.mimicry"))

        guard case let .succeeded(summary) = model.packageState else {
            XCTFail("Expected opened package to succeed")
            return
        }

        XCTAssertEqual(model.recentPackages.map(\.name), ["opened.mimicry"])
        XCTAssertEqual(summary.safeCount, 1)
        XCTAssertEqual(summary.reviewCount, 3)
        XCTAssertEqual(summary.excludedCount, 1)
        XCTAssertEqual(summary.unsupportedCount, 1)
        XCTAssertEqual(summary.compatibility.managedCount, 1)
        XCTAssertEqual(summary.compatibility.unsupportedCount, 1)
        XCTAssertEqual(summary.sections.map(\.name), ["Environment", "Browser"])
        XCTAssertEqual(summary.sections.first?.warnings.first?.message, "Review environment")
        XCTAssertEqual(summary.sections.first?.items.map(\.key), ["safe", "hostname", "review", "excluded"])
        XCTAssertEqual(summary.sections.first?.items.first?.classification, "Safe Configuration")
        XCTAssertEqual(summary.sections.first?.items.map(\.isInformationalOnly), [true, true, true, true])
        XCTAssertEqual(summary.sections.last?.items.map(\.isInformationalOnly), [false, false])
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
            planApplyPackage: { _ in Self.sampleApplyPlanSummary() },
            confirmedApplyPackage: { url in Self.sampleConfirmedApplySummary(packageURL: url) },
            exportBrowserBookmarks: { packageURL, outputURL in
                Self.sampleBrowserBookmarkExportSummary(packageURL: packageURL, outputURL: outputURL)
            },
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
                planApplyPackage: { url in Self.sampleApplyPlanSummary(url: url) },
                confirmedApplyPackage: { url in Self.sampleConfirmedApplySummary(packageURL: url) },
                exportBrowserBookmarks: { packageURL, outputURL in
                    Self.sampleBrowserBookmarkExportSummary(packageURL: packageURL, outputURL: outputURL)
                },
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
        XCTAssertEqual(expected.missingCount, 1)
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
            planApplyPackage: { _ in Self.sampleApplyPlanSummary() },
            confirmedApplyPackage: { url in Self.sampleConfirmedApplySummary(packageURL: url) },
            exportBrowserBookmarks: { packageURL, outputURL in
                Self.sampleBrowserBookmarkExportSummary(packageURL: packageURL, outputURL: outputURL)
            },
            detectCapabilities: { Self.sampleCapabilities }
        ))

        await model.openPackage(at: URL(fileURLWithPath: "/tmp/opened.mimicry"))
        await model.compareCurrentPackage()

        XCTAssertEqual(model.compareState, .failed("Compare test failure"))
    }

    func testPlanApplyRequiresOpenPackage() async {
        let model = Self.makeModel()

        await model.planApplyForCurrentPackage()

        XCTAssertEqual(model.applyPlanState, .failed("Open a package before planning apply."))
    }

    func testPlanApplySummarizesDryRunActions() async {
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
                planApplyPackage: { url in Self.sampleApplyPlanSummary(url: url) },
                confirmedApplyPackage: { url in Self.sampleConfirmedApplySummary(packageURL: url) },
                exportBrowserBookmarks: { packageURL, outputURL in
                    Self.sampleBrowserBookmarkExportSummary(packageURL: packageURL, outputURL: outputURL)
                },
                detectCapabilities: { Self.sampleCapabilities }
            ),
            historyStore: PackageHistoryStore(
                load: { [] },
                record: { [RecentPackage(url: $0)] }
            )
        )

        await model.openPackage(at: URL(fileURLWithPath: "/tmp/opened.mimicry"))
        await model.planApplyForCurrentPackage()

        guard case let .succeeded(summary) = model.applyPlanState else {
            return XCTFail("Expected dry-run apply plan to succeed.")
        }

        XCTAssertEqual(summary.packageURL, URL(fileURLWithPath: "/tmp/opened.mimicry"))
        XCTAssertEqual(summary.referenceSource, "source-mac (cmb)")
        XCTAssertEqual(summary.currentSource, "current-mac (cmb)")
        XCTAssertEqual(summary.actionCount, 2)
        XCTAssertEqual(summary.installCount, 0)
        XCTAssertEqual(summary.configureCount, 0)
        XCTAssertEqual(summary.skipCount, 1)
        XCTAssertEqual(summary.blockedCount, 1)
        XCTAssertEqual(summary.userActionCount, 0)
        XCTAssertEqual(summary.compatibility.unsupportedCount, 1)
        XCTAssertEqual(summary.groups.map(\.title), ["SKIP", "BLOCKED"])
        XCTAssertEqual(
            summary.groups.first?.actions.first?.detail,
            "Environment metadata is informational and is not applied."
        )
    }

    func testCompatibilitySummaryCountsManagedMachineHardwareAndUserSpecificItems() {
        let summary = AppCompatibilitySummary(items: [
            SnapshotItem(key: "managed", value: .string("yes"), classification: .managed),
            SnapshotItem(key: "machine", value: .string("host"), classification: .machineSpecific),
            SnapshotItem(
                key: "hardware",
                value: .string("arm64"),
                classification: .hardwareSpecific,
                applicability: .appleSiliconOnly
            ),
            SnapshotItem(
                key: "user",
                value: .string("cmb"),
                classification: .userMustReview,
                applicability: .userSpecific
            ),
            SnapshotItem(key: "unsupported", value: .absent, classification: .unsupported)
        ])

        XCTAssertEqual(summary.managedCount, 1)
        XCTAssertEqual(summary.machineSpecificCount, 1)
        XCTAssertEqual(summary.hardwareSpecificCount, 1)
        XCTAssertEqual(summary.userSpecificCount, 1)
        XCTAssertEqual(summary.unsupportedCount, 1)
        XCTAssertTrue(summary.hasConstrainedItems)
    }

    func testPlanApplyReportsFailure() async {
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
            comparePackage: { url in Self.sampleCompareSummary(url: url) },
            planApplyPackage: { _ in throw AppTestError.applyFailed },
            confirmedApplyPackage: { url in Self.sampleConfirmedApplySummary(packageURL: url) },
            exportBrowserBookmarks: { packageURL, outputURL in
                Self.sampleBrowserBookmarkExportSummary(packageURL: packageURL, outputURL: outputURL)
            },
            detectCapabilities: { Self.sampleCapabilities }
        ))

        await model.openPackage(at: URL(fileURLWithPath: "/tmp/opened.mimicry"))
        await model.planApplyForCurrentPackage()

        XCTAssertEqual(model.applyPlanState, .failed("Apply test failure"))
    }

    func testConfirmedApplyRequiresOpenPackage() async {
        let model = Self.makeModel()

        await model.confirmedApplyForCurrentPackage()

        XCTAssertEqual(model.confirmedApplyState, .failed("Open a package before confirmed apply."))
    }

    func testConfirmedApplyRequiresDryRun() async {
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
                planApplyPackage: { url in Self.sampleApplyPlanSummary(url: url) },
                confirmedApplyPackage: { url in Self.sampleConfirmedApplySummary(packageURL: url) },
                exportBrowserBookmarks: { packageURL, outputURL in
                    Self.sampleBrowserBookmarkExportSummary(packageURL: packageURL, outputURL: outputURL)
                },
                detectCapabilities: { Self.sampleCapabilities }
            )
        )

        await model.openPackage(at: URL(fileURLWithPath: "/tmp/opened.mimicry"))
        await model.confirmedApplyForCurrentPackage()

        XCTAssertEqual(model.confirmedApplyState, .failed("Run a dry run before confirmed apply."))
    }

    func testConfirmedApplySummarizesFinderSafeResults() async {
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
                planApplyPackage: { url in Self.sampleApplyPlanSummary(url: url) },
                confirmedApplyPackage: { url in Self.sampleConfirmedApplySummary(packageURL: url) },
                exportBrowserBookmarks: { packageURL, outputURL in
                    Self.sampleBrowserBookmarkExportSummary(packageURL: packageURL, outputURL: outputURL)
                },
                detectCapabilities: { Self.sampleCapabilities }
            ),
            historyStore: PackageHistoryStore(
                load: { [] },
                record: { [RecentPackage(url: $0)] }
            )
        )

        await model.openPackage(at: URL(fileURLWithPath: "/tmp/opened.mimicry"))
        await model.planApplyForCurrentPackage()
        await model.confirmedApplyForCurrentPackage()

        XCTAssertEqual(
            model.confirmedApplyState,
            .succeeded(Self.sampleConfirmedApplySummary(packageURL: URL(fileURLWithPath: "/tmp/opened.mimicry")))
        )

        guard case let .succeeded(summary) = model.confirmedApplyState else {
            return XCTFail("Expected confirmed apply to succeed.")
        }

        XCTAssertEqual(summary.backupURL, URL(fileURLWithPath: "/tmp/finder-backup.json"))
        XCTAssertEqual(summary.resultCount, 2)
        XCTAssertEqual(summary.appliedCount, 1)
        XCTAssertEqual(summary.warningCount, 1)
        XCTAssertEqual(summary.skippedCount, 0)
        XCTAssertEqual(summary.failedCount, 0)
    }

    func testConfirmedApplyReportsFailure() async {
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
            comparePackage: { url in Self.sampleCompareSummary(url: url) },
            planApplyPackage: { url in Self.sampleApplyPlanSummary(url: url) },
            confirmedApplyPackage: { _ in throw AppTestError.confirmedApplyFailed },
            exportBrowserBookmarks: { packageURL, outputURL in
                Self.sampleBrowserBookmarkExportSummary(packageURL: packageURL, outputURL: outputURL)
            },
            detectCapabilities: { Self.sampleCapabilities }
        ))

        await model.openPackage(at: URL(fileURLWithPath: "/tmp/opened.mimicry"))
        await model.planApplyForCurrentPackage()
        await model.confirmedApplyForCurrentPackage()

        XCTAssertEqual(model.confirmedApplyState, .failed("Confirmed apply test failure"))
    }

    func testBrowserBookmarkExportRequiresOpenPackage() async {
        let model = Self.makeModel()

        await model.exportBrowserBookmarksForCurrentPackage(to: URL(fileURLWithPath: "/tmp/bookmarks.html"))

        XCTAssertEqual(model.browserBookmarkExportState, .failed("Open a package before exporting browser bookmarks."))
    }

    func testBrowserBookmarkExportSummarizesHTMLHandoff() async {
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
                planApplyPackage: { url in Self.sampleApplyPlanSummary(url: url) },
                confirmedApplyPackage: { url in Self.sampleConfirmedApplySummary(packageURL: url) },
                exportBrowserBookmarks: { packageURL, outputURL in
                    Self.sampleBrowserBookmarkExportSummary(packageURL: packageURL, outputURL: outputURL)
                },
                detectCapabilities: { Self.sampleCapabilities }
            ),
            historyStore: PackageHistoryStore(
                load: { [] },
                record: { [RecentPackage(url: $0)] }
            )
        )

        await model.openPackage(at: URL(fileURLWithPath: "/tmp/opened.mimicry"))
        await model.exportBrowserBookmarksForCurrentPackage(to: URL(fileURLWithPath: "/tmp/bookmarks.html"))

        XCTAssertEqual(
            model.browserBookmarkExportState,
            .succeeded(Self.sampleBrowserBookmarkExportSummary(
                packageURL: URL(fileURLWithPath: "/tmp/opened.mimicry"),
                outputURL: URL(fileURLWithPath: "/tmp/bookmarks.html")
            ))
        )
    }

    func testBrowserBookmarkExportReportsFailure() async {
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
            comparePackage: { url in Self.sampleCompareSummary(url: url) },
            planApplyPackage: { url in Self.sampleApplyPlanSummary(url: url) },
            confirmedApplyPackage: { url in Self.sampleConfirmedApplySummary(packageURL: url) },
            exportBrowserBookmarks: { _, _ in throw AppTestError.browserExportFailed },
            detectCapabilities: { Self.sampleCapabilities }
        ))

        await model.openPackage(at: URL(fileURLWithPath: "/tmp/opened.mimicry"))
        await model.exportBrowserBookmarksForCurrentPackage(to: URL(fileURLWithPath: "/tmp/bookmarks.html"))

        XCTAssertEqual(model.browserBookmarkExportState, .failed("Browser export test failure"))
    }

    func testAuditLogRecordsApplyAndBrowserHandoffActivity() async {
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
                planApplyPackage: { url in Self.sampleApplyPlanSummary(url: url) },
                confirmedApplyPackage: { url in Self.sampleConfirmedApplySummary(packageURL: url) },
                exportBrowserBookmarks: { packageURL, outputURL in
                    Self.sampleBrowserBookmarkExportSummary(packageURL: packageURL, outputURL: outputURL)
                },
                detectCapabilities: { Self.sampleCapabilities }
            ),
            historyStore: PackageHistoryStore(
                load: { [] },
                record: { [RecentPackage(url: $0)] }
            )
        )

        await model.openPackage(at: URL(fileURLWithPath: "/tmp/opened.mimicry"))
        await model.planApplyForCurrentPackage()
        await model.confirmedApplyForCurrentPackage()
        await model.exportBrowserBookmarksForCurrentPackage(to: URL(fileURLWithPath: "/tmp/bookmarks.html"))

        XCTAssertEqual(model.auditLog.map(\.operation), [
            .browserBookmarkExport,
            .confirmedApply,
            .dryRunApply,
            .openPackage
        ])
        XCTAssertEqual(model.auditLog.map(\.status), ["success", "success", "success", "success"])
        XCTAssertEqual(model.auditLog[0].metrics["bookmarksExported"], 7)
        XCTAssertEqual(model.auditLog[1].backupURL, URL(fileURLWithPath: "/tmp/finder-backup.json"))
        XCTAssertEqual(model.auditLog[1].metrics["applied"], 1)
        XCTAssertEqual(model.auditLog[2].metrics["actions"], 2)
    }

    func testAuditLogExportWritesStructuredJSON() async throws {
        let model = Self.makeModel()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("mimicry-audit-log.json")

        await model.openPackage(at: URL(fileURLWithPath: "/tmp/opened.mimicry"))
        await model.planApplyForCurrentPackage()
        model.exportAuditLog(to: outputURL)

        XCTAssertEqual(model.auditExportState, .succeeded(AppAuditExportSummary(outputURL: outputURL, entryCount: 2)))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(DecodedAuditDocument.self, from: Data(contentsOf: outputURL))

        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.entries.map(\.operation), [.dryRunApply, .openPackage])
        XCTAssertEqual(document.entries.first?.packageURL, URL(fileURLWithPath: "/tmp/opened.mimicry"))
        XCTAssertEqual(document.entries.first?.metrics["actions"], 2)
    }

    func testAuditLogExportRequiresEntries() {
        let model = Self.makeModel()

        model.exportAuditLog(to: URL(fileURLWithPath: "/tmp/mimicry-audit-log.json"))

        XCTAssertEqual(model.auditExportState, .failed("No audit entries to export."))
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
            planApplyPackage: { _ in Self.sampleApplyPlanSummary() },
            confirmedApplyPackage: { url in Self.sampleConfirmedApplySummary(packageURL: url) },
            exportBrowserBookmarks: { packageURL, outputURL in
                Self.sampleBrowserBookmarkExportSummary(packageURL: packageURL, outputURL: outputURL)
            },
            detectCapabilities: { Self.sampleCapabilities }
        ))

        await model.refreshDiagnostics()

        let expected = AppDiagnosticsSummary(capabilities: Self.sampleCapabilities)
        XCTAssertEqual(model.diagnosticsState, .succeeded(expected))
        XCTAssertTrue(expected.rows.contains(DiagnosticRow(label: "Homebrew", value: "Available")))
        XCTAssertTrue(expected.rows.contains(DiagnosticRow(label: "Management", value: "Managed")))
        XCTAssertTrue(expected.managementDetail.contains("managed"))
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
            planApplyPackage: { url in sampleApplyPlanSummary(url: url) },
            confirmedApplyPackage: { url in sampleConfirmedApplySummary(packageURL: url) },
            exportBrowserBookmarks: { packageURL, outputURL in
                sampleBrowserBookmarkExportSummary(packageURL: packageURL, outputURL: outputURL)
            },
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
                            SnapshotItem(key: "hostname", value: .string("source-mac"), classification: .machineSpecific),
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

    nonisolated private static func sampleApplyPlanSummary(
        url: URL = URL(fileURLWithPath: "/tmp/opened.mimicry")
    ) -> AppApplyPlanSummary {
        AppApplyPlanSummary(
            packageURL: url,
            plan: SnapshotApplyPlanner().plan(
                reference: samplePackage(url: url).snapshot,
                current: sampleCurrentSnapshot()
            )
        )
    }

    nonisolated private static func sampleBrowserBookmarkExportSummary(
        packageURL: URL = URL(fileURLWithPath: "/tmp/opened.mimicry"),
        outputURL: URL = URL(fileURLWithPath: "/tmp/bookmarks.html")
    ) -> AppBrowserBookmarkExportSummary {
        AppBrowserBookmarkExportSummary(
            packageURL: packageURL,
            result: BrowserBookmarkImportResult(
                outputURL: outputURL,
                summary: BrowserBookmarkImportSummary(
                    browserSectionCount: 3,
                    exportedBookmarkCount: 7,
                    skippedDuplicateCount: 1,
                    skippedInvalidCount: 2,
                    skippedUnavailableSourceCount: 1
                )
            )
        )
    }

    nonisolated private static func sampleConfirmedApplySummary(
        packageURL: URL = URL(fileURLWithPath: "/tmp/opened.mimicry")
    ) -> AppConfirmedApplySummary {
        AppConfirmedApplySummary(
            packageURL: packageURL,
            summary: FinderPreferenceApplySummary(
                backupURL: URL(fileURLWithPath: "/tmp/finder-backup.json"),
                results: [
                    ApplyResult(
                        actionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                        status: .success,
                        message: "Applied Finder preference AppleShowAllFiles."
                    ),
                    ApplyResult(
                        actionID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                        status: .warning,
                        message: "Finder preference ShowPathbar could not be applied."
                    )
                ]
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

private struct DecodedAuditDocument: Decodable {
    var schemaVersion: Int
    var entries: [AppAuditLogEntry]
}

private enum AppTestError: LocalizedError {
    case snapshotFailed
    case packageFailed
    case compareFailed
    case applyFailed
    case confirmedApplyFailed
    case browserExportFailed

    var errorDescription: String? {
        switch self {
        case .snapshotFailed:
            "Snapshot test failure"
        case .packageFailed:
            "Package test failure"
        case .compareFailed:
            "Compare test failure"
        case .applyFailed:
            "Apply test failure"
        case .confirmedApplyFailed:
            "Confirmed apply test failure"
        case .browserExportFailed:
            "Browser export test failure"
        }
    }
}
