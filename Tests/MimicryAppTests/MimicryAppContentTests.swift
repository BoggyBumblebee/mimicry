import AppKit
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
        let host = NSHostingView(rootView: DetailView(section: .dashboard))
        host.frame = CGRect(x: 0, y: 0, width: 900, height: 640)

        host.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(host.fittingSize.width, 0)
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testEverySectionDetailCanBeHosted() {
        for section in AppSection.allCases {
            let host = NSHostingView(rootView: DetailView(section: section))
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
}
