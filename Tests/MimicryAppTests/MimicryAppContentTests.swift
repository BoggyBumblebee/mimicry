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
    }

    func testSnapshotActionReportsFailure() async {
        let model = Self.makeModel(runtime: AppRuntime(
            createSnapshot: { _ in throw AppTestError.snapshotFailed },
            detectCapabilities: { Self.sampleCapabilities }
        ))

        await model.createSnapshot(to: URL(fileURLWithPath: "/tmp/gui-snapshot.mimicry"))

        XCTAssertEqual(model.snapshotState, .failed("Snapshot test failure"))
        XCTAssertTrue(model.recentPackages.isEmpty)
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
}

private enum AppTestError: LocalizedError {
    case snapshotFailed

    var errorDescription: String? {
        "Snapshot test failure"
    }
}
