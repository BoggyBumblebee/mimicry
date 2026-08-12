import AppKit
import MimicryCore
import SwiftUI

@main
struct MimicryApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .commands {
            SidebarCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

struct RootView: View {
    @StateObject private var model: AppModel
    @State private var selection: AppSection? = .dashboard

    init(model: AppModel = AppModel()) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection)
        } detail: {
            DetailView(section: selection ?? .dashboard, model: model)
        }
        .frame(minWidth: 980, minHeight: 660)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    selection = .snapshot
                } label: {
                    Label("Snapshot", systemImage: "camera.viewfinder")
                }
                .help("Go to Snapshot")

                Button {
                    selection = .diagnostics
                } label: {
                    Label("Doctor", systemImage: "stethoscope")
                }
                .help("Go to Diagnostics")
            }
        }
    }
}

private struct Sidebar: View {
    @Binding var selection: AppSection?

    var body: some View {
        List(AppSection.allCases, selection: $selection) { section in
            Label(section.title, systemImage: section.systemImage)
                .tag(section)
        }
        .navigationTitle("Mimicry")
        .listStyle(.sidebar)
    }
}

struct DetailView: View {
    var section: AppSection
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeader(section: section)

                switch section {
                case .dashboard:
                    DashboardView(model: model)
                case .snapshot:
                    SnapshotView(model: model)
                case .apply:
                    ApplyView()
                case .compare:
                    CompareView(model: model)
                case .history:
                    HistoryView(model: model)
                case .diagnostics:
                    DiagnosticsView(model: model)
                }
            }
            .padding(28)
            .frame(maxWidth: 1120, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(section.title)
    }
}

private struct SectionHeader: View {
    var section: AppSection

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: section.systemImage)
                .font(.system(size: 28, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .font(.largeTitle.weight(.semibold))
                Text(section.subtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

private struct DashboardView: View {
    @ObservedObject var model: AppModel
    private let summaries = CapabilitySummary.current
    private let workflow = WorkflowStep.current

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StatusBand(
                title: "Phase 4 Complete",
                detail: "Review-first browser capture, dry-run planning, and HTML handoff are in place. The only confirmed mutation path remains Finder-safe preferences."
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                ForEach(summaries) { summary in
                    MetricCard(summary: summary)
                }
                MetricCard(summary: CapabilitySummary(
                    title: "Packages",
                    status: "\(model.recentPackages.count) recent",
                    detail: model.recentPackages.first?.name ?? "Create a snapshot to start package history.",
                    systemImage: "archivebox",
                    tint: .teal
                ))
            }

            ContentPanel(title: "Workflow", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
                VStack(spacing: 0) {
                    ForEach(workflow) { step in
                        WorkflowRow(step: step)
                        if step.id != workflow.last?.id {
                            Divider()
                                .padding(.leading, 36)
                        }
                    }
                }
            }
        }
    }
}

private struct SnapshotView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TwoColumnPanels {
            ContentPanel(title: "Capture", systemImage: "camera.viewfinder") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Button {
                            guard let outputURL = SnapshotSavePanel.outputURL() else {
                                return
                            }
                            Task {
                                await model.createSnapshot(to: outputURL)
                            }
                        } label: {
                            Label("Create Snapshot...", systemImage: "camera.viewfinder")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.snapshotState.isRunning)

                        Button {
                            guard let packageURL = PackageOpenPanel.packageURL() else {
                                return
                            }
                            Task {
                                await model.openPackage(at: packageURL)
                            }
                        } label: {
                            Label("Open Package...", systemImage: "folder")
                        }
                        .disabled(model.packageState.isRunning)
                    }

                    ActionList(items: [
                        ActionItem(title: "Environment", status: "Captured", systemImage: "macbook"),
                        ActionItem(title: "Homebrew", status: "Captured", systemImage: "shippingbox"),
                        ActionItem(title: "App Store", status: "Captured", systemImage: "bag"),
                        ActionItem(title: "Finder", status: "Captured", systemImage: "folder"),
                        ActionItem(title: "Terminal", status: "Reviewed", systemImage: "terminal"),
                        ActionItem(title: "iCloud", status: "User action", systemImage: "icloud"),
                        ActionItem(title: "Browsers", status: "Review only", systemImage: "safari")
                    ])
                }
            }

            ContentPanel(title: "Snapshot Result", systemImage: "checkmark.seal") {
                SnapshotResultView(state: model.snapshotState)
            }

            ContentPanel(title: "Package Review", systemImage: "doc.text.magnifyingglass") {
                PackageInspectView(state: model.packageState)
            }
        }
    }
}

private struct ApplyView: View {
    var body: some View {
        TwoColumnPanels {
            ContentPanel(title: "Confirmed Apply", systemImage: "checkmark.shield") {
                ActionList(items: [
                    ActionItem(title: "Finder booleans", status: "Enabled", systemImage: "checkmark.circle"),
                    ActionItem(title: "Finder strings", status: "Enabled", systemImage: "checkmark.circle"),
                    ActionItem(title: "Backup before write", status: "Required", systemImage: "externaldrive"),
                    ActionItem(title: "Deletes", status: "Blocked", systemImage: "nosign")
                ])
            }

            ContentPanel(title: "Review Required", systemImage: "person.crop.circle.badge.exclamationmark") {
                ActionList(items: [
                    ActionItem(title: "Homebrew installs", status: "Dry-run only", systemImage: "shippingbox"),
                    ActionItem(title: "App Store apps", status: "Dry-run only", systemImage: "bag"),
                    ActionItem(title: "Terminal files", status: "Review only", systemImage: "terminal"),
                    ActionItem(title: "Browser imports", status: "HTML handoff", systemImage: "safari")
                ])
            }
        }
    }
}

private struct CompareView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TwoColumnPanels {
            ContentPanel(title: "Package", systemImage: "doc.text.magnifyingglass") {
                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        Task {
                            await model.compareCurrentPackage()
                        }
                    } label: {
                        Label("Compare", systemImage: "square.split.2x1")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCompare)

                    PackageInspectView(state: model.packageState)
                }
            }

            ContentPanel(title: "Diff Result", systemImage: "square.split.2x1") {
                CompareResultView(state: model.compareState)
            }
        }
    }

    private var canCompare: Bool {
        guard !model.compareState.isRunning else {
            return false
        }

        if case .succeeded = model.packageState {
            return true
        }

        return false
    }
}

private struct HistoryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TwoColumnPanels {
            ContentPanel(title: "Recent Packages", systemImage: "archivebox") {
                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        guard let packageURL = PackageOpenPanel.packageURL() else {
                            return
                        }
                        Task {
                            await model.openPackage(at: packageURL)
                        }
                    } label: {
                        Label("Open Package...", systemImage: "folder")
                    }
                    .disabled(model.packageState.isRunning)

                    if model.recentPackages.isEmpty {
                        EmptyStateRow(
                            title: "No packages yet",
                            detail: "Snapshot and open-package activity will appear here.",
                            systemImage: "tray"
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(model.recentPackages) { package in
                                RecentPackageRow(package: package) {
                                    Task {
                                        await model.openPackage(at: package.url)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ContentPanel(title: "Current Package", systemImage: "doc.text.magnifyingglass") {
                PackageInspectView(state: model.packageState)
            }

            ContentPanel(title: "Recent Milestones", systemImage: "clock.arrow.circlepath") {
                VStack(alignment: .leading, spacing: 12) {
                    MilestoneRow(title: "GUI polish", detail: "Dashboard shell and app tests", commit: "cf67945")
                    MilestoneRow(title: "Phase 4 closeout", detail: "Browser provider phase complete", commit: "92ae7f2")
                    MilestoneRow(title: "Browser dry-run handoff", detail: "Apply preview links to export command", commit: "4f499d5")
                }
            }
        }
    }
}

private struct DiagnosticsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TwoColumnPanels {
            ContentPanel(title: "Doctor Signals", systemImage: "stethoscope") {
                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        Task {
                            await model.refreshDiagnostics()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.diagnosticsState.isRunning)

                    DiagnosticsResultView(state: model.diagnosticsState)
                }
            }

            ContentPanel(title: "Quality", systemImage: "checkmark.seal") {
                KeyValueList(rows: [
                    KeyValueRow(label: "CI", value: "Passing"),
                    KeyValueRow(label: "SonarCloud", value: "Passing"),
                    KeyValueRow(label: "Open issues", value: "0"),
                    KeyValueRow(label: "Coverage", value: "93.7%")
                ])
            }
        }
    }
}

struct SettingsView: View {
    @AppStorage("requireExplicitConfirmation") private var requireExplicitConfirmation = true
    @AppStorage("showAdvancedDiagnostics") private var showAdvancedDiagnostics = false

    var body: some View {
        Form {
            Toggle("Require explicit confirmation before apply", isOn: $requireExplicitConfirmation)
            Toggle("Show advanced diagnostics", isOn: $showAdvancedDiagnostics)
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460)
    }
}

private struct TwoColumnPanels<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
            content
        }
    }
}

private struct StatusBand: View {
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ContentPanel<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        }
    }
}

private struct MetricCard: View {
    var summary: CapabilitySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(summary.title, systemImage: summary.systemImage)
                    .font(.headline)
                Spacer()
                Text(summary.status)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(summary.tint.opacity(0.16), in: Capsule())
                    .foregroundStyle(summary.tint)
            }

            Text(summary.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        }
    }
}

private struct WorkflowRow: View {
    var step: WorkflowStep

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step.systemImage)
                .frame(width: 24)
                .foregroundStyle(step.tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.subheadline.weight(.semibold))
                Text(step.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 10)
    }
}

private struct ActionList: View {
    var items: [ActionItem]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(items) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.systemImage)
                        .frame(width: 22)
                        .foregroundStyle(.secondary)
                    Text(item.title)
                    Spacer()
                    Text(item.status)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
    }
}

private struct KeyValueList: View {
    var rows: [KeyValueRow]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows) { row in
                LabeledContent(row.label, value: row.value)
                    .font(.subheadline)
            }
        }
    }
}

private struct SnapshotResultView: View {
    var state: AppCommandState<AppSnapshotSummary>

    var body: some View {
        switch state {
        case .idle:
            KeyValueList(rows: [
                KeyValueRow(label: "Format", value: ".mimicry package"),
                KeyValueRow(label: "Checksums", value: "Manifest backed"),
                KeyValueRow(label: "Secrets", value: "Redacted or excluded"),
                KeyValueRow(label: "Browser URLs", value: "Queries and fragments removed")
            ])
        case .running:
            ProgressRow(title: "Creating snapshot", detail: "No system settings are being changed.")
        case let .succeeded(summary):
            VStack(alignment: .leading, spacing: 14) {
                KeyValueList(rows: [
                    KeyValueRow(label: "Package", value: summary.url.lastPathComponent),
                    KeyValueRow(label: "Sections", value: "\(summary.sectionCount)"),
                    KeyValueRow(label: "Items", value: "\(summary.itemCount)"),
                    KeyValueRow(label: "Warnings", value: "\(summary.warningCount)"),
                    KeyValueRow(label: "Source", value: summary.source)
                ])

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([summary.url])
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
            }
        case let .failed(message):
            FailureRow(title: "Snapshot failed", detail: message)
        }
    }
}

private struct PackageInspectView: View {
    var state: AppCommandState<AppPackageSummary>

    var body: some View {
        switch state {
        case .idle:
            EmptyStateRow(title: "No package open", detail: "Open a .mimicry package to inspect its contents.", systemImage: "doc")
        case .running:
            ProgressRow(title: "Opening package", detail: "Validating manifest and checksums.")
        case let .succeeded(summary):
            VStack(alignment: .leading, spacing: 14) {
                KeyValueList(rows: [
                    KeyValueRow(label: "Package", value: summary.packageName),
                    KeyValueRow(label: "Source", value: summary.source),
                    KeyValueRow(label: "macOS", value: summary.macOSVersion),
                    KeyValueRow(label: "Architecture", value: summary.architecture),
                    KeyValueRow(label: "Sections", value: "\(summary.sectionCount)"),
                    KeyValueRow(label: "Items", value: "\(summary.itemCount)"),
                    KeyValueRow(label: "Warnings", value: "\(summary.warningCount)")
                ])

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                    CompactStatusTile(title: "Safe", value: "\(summary.safeCount)", systemImage: "checkmark.circle")
                    CompactStatusTile(title: "Review", value: "\(summary.reviewCount)", systemImage: "person.crop.circle.badge.exclamationmark")
                    CompactStatusTile(title: "Excluded", value: "\(summary.excludedCount)", systemImage: "forward.end.circle")
                    CompactStatusTile(title: "Unsupported", value: "\(summary.unsupportedCount)", systemImage: "xmark.octagon")
                }

                if !summary.sections.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(summary.sections.prefix(8)) { section in
                            PackageSectionRow(section: section)
                        }
                    }
                }

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([summary.url])
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
            }
        case let .failed(message):
            FailureRow(title: "Package could not be opened", detail: message)
        }
    }
}

private struct PackageSectionRow: View {
    var section: PackageSectionSummary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.stack")
                .frame(width: 22)
                .foregroundStyle(.secondary)
            Text(section.name)
            Spacer()
            Text("\(section.itemCount) items")
                .foregroundStyle(.secondary)
            if section.warningCount > 0 {
                Text("\(section.warningCount) warnings")
                    .foregroundStyle(.orange)
            }
        }
        .font(.subheadline)
    }
}

private struct CompareResultView: View {
    var state: AppCommandState<AppCompareSummary>

    var body: some View {
        switch state {
        case .idle:
            VStack(alignment: .leading, spacing: 14) {
                EmptyStateRow(title: "No comparison yet", detail: "Open a package and compare it with this Mac.", systemImage: "square.split.2x1")
                DiffGroupGrid(summary: nil)
            }
        case .running:
            ProgressRow(title: "Comparing package", detail: "Building a current snapshot without changing settings.")
        case let .succeeded(summary):
            VStack(alignment: .leading, spacing: 14) {
                KeyValueList(rows: [
                    KeyValueRow(label: "Package", value: summary.packageURL.lastPathComponent),
                    KeyValueRow(label: "Reference", value: summary.referenceSource),
                    KeyValueRow(label: "Current", value: summary.currentSource),
                    KeyValueRow(label: "Sections", value: "\(summary.sectionCount)"),
                    KeyValueRow(label: "Items", value: "\(summary.itemCount)")
                ])

                DiffGroupGrid(summary: summary)

                if !summary.sections.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(summary.sections.prefix(8)) { section in
                            CompareSectionRow(section: section)
                        }
                    }
                }
            }
        case let .failed(message):
            FailureRow(title: "Comparison failed", detail: message)
        }
    }
}

private struct DiffGroupGrid: View {
    var summary: AppCompareSummary?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
            CompactStatusTile(title: "Matching", value: value(\.matchingCount), systemImage: "equal.circle")
            CompactStatusTile(title: "Changed", value: value(\.changedCount), systemImage: "arrow.triangle.2.circlepath")
            CompactStatusTile(title: "Missing", value: value(\.missingCount), systemImage: "plus.circle")
            CompactStatusTile(title: "Current Only", value: value(\.currentOnlyCount), systemImage: "minus.circle")
            CompactStatusTile(title: "Skipped", value: value(\.skippedCount), systemImage: "forward.end.circle")
            CompactStatusTile(title: "Blocked", value: value(\.blockedCount), systemImage: "xmark.octagon")
        }
    }

    private func value(_ keyPath: KeyPath<AppCompareSummary, Int>) -> String {
        guard let summary else {
            return "-"
        }

        return "\(summary[keyPath: keyPath])"
    }
}

private struct CompareSectionRow: View {
    var section: CompareSectionSummary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.stack")
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.name)
                Text(sectionDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if section.warningCount > 0 {
                Text("\(section.warningCount) warnings")
                    .foregroundStyle(.orange)
            }
        }
        .font(.subheadline)
    }

    private var sectionDetail: String {
        [
            "\(section.itemCount) items",
            "\(section.matchingCount) matching",
            "\(section.changedCount) changed",
            "\(section.missingCount) missing",
            "\(section.currentOnlyCount) current only",
            "\(section.skippedCount) skipped",
            "\(section.blockedCount) blocked"
        ].joined(separator: " / ")
    }
}

private struct DiagnosticsResultView: View {
    var state: AppCommandState<AppDiagnosticsSummary>

    var body: some View {
        switch state {
        case .idle:
            EmptyStateRow(title: "Not refreshed", detail: "Doctor signals will appear here.", systemImage: "stethoscope")
        case .running:
            ProgressRow(title: "Refreshing diagnostics", detail: "Reading local capability signals.")
        case let .succeeded(summary):
            VStack(alignment: .leading, spacing: 12) {
                KeyValueList(rows: [
                    KeyValueRow(label: "Host", value: summary.host),
                    KeyValueRow(label: "macOS", value: summary.macOSVersion),
                    KeyValueRow(label: "Architecture", value: summary.architecture)
                ])

                Divider()

                KeyValueList(rows: summary.rows.map { row in
                    KeyValueRow(label: row.label, value: row.value)
                })
            }
        case let .failed(message):
            FailureRow(title: "Diagnostics failed", detail: message)
        }
    }
}

private struct ProgressRow: View {
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FailureRow: View {
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct EmptyStateRow: View {
    var title: String
    var detail: String
    var systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CompactStatusTile: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct RecentPackageRow: View {
    var package: RecentPackage
    var open: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.badge.gearshape")
                .foregroundStyle(Color.accentColor)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(package.name)
                    .font(.subheadline.weight(.semibold))
                Text(package.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: open) {
                Image(systemName: "doc.text.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Inspect")

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([package.url])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Reveal")
        }
    }
}

private enum PackageOpenPanel {
    @MainActor
    static func packageURL() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Open Mimicry Package"
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return url
    }
}

private struct MilestoneRow: View {
    var title: String
    var detail: String
    var commit: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(commit)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}

private enum SnapshotSavePanel {
    @MainActor
    static func outputURL() -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mimicry-snapshot.mimicry"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Create Mimicry Snapshot"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        if url.pathExtension == "mimicry" {
            return url
        }

        return url.deletingPathExtension().appendingPathExtension("mimicry")
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case snapshot
    case apply
    case compare
    case history
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:
            "Dashboard"
        case .snapshot:
            "Snapshot"
        case .apply:
            "Apply"
        case .compare:
            "Compare"
        case .history:
            "History"
        case .diagnostics:
            "Diagnostics"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard:
            "Current project state and trusted workflow."
        case .snapshot:
            "Capture the reviewable parts of this Mac."
        case .apply:
            "Plan changes first, then apply only the approved safe slice."
        case .compare:
            "Compare a package with the current Mac."
        case .history:
            "Track completed milestones and package activity."
        case .diagnostics:
            "Check local tools, services, and quality signals."
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:
            "rectangle.3.group"
        case .snapshot:
            "camera.viewfinder"
        case .apply:
            "arrow.down.doc"
        case .compare:
            "square.split.2x1"
        case .history:
            "clock.arrow.circlepath"
        case .diagnostics:
            "stethoscope"
        }
    }
}

struct CapabilitySummary: Identifiable {
    var id: String { title }
    var title: String
    var status: String
    var detail: String
    var systemImage: String
    var tint: Color

    static let current = [
        CapabilitySummary(
            title: "Providers",
            status: "9 ready",
            detail: "Environment, Homebrew, App Store, Finder, Terminal, iCloud, Safari, Chrome, and Firefox.",
            systemImage: "square.stack.3d.up",
            tint: .blue
        ),
        CapabilitySummary(
            title: "Apply",
            status: "Narrow",
            detail: "Confirmed writes are limited to backed-up Finder boolean and string preferences.",
            systemImage: "checkmark.shield",
            tint: .green
        ),
        CapabilitySummary(
            title: "Browsers",
            status: "Handoff",
            detail: "Bookmarks are captured safely and restored through a reviewable HTML import artifact.",
            systemImage: "safari",
            tint: .orange
        ),
        CapabilitySummary(
            title: "Quality",
            status: "Green",
            detail: "CI and SonarCloud are passing with zero open Sonar issues.",
            systemImage: "checkmark.seal",
            tint: .green
        )
    ]
}

struct WorkflowStep: Identifiable {
    var id: String { title }
    var title: String
    var detail: String
    var systemImage: String
    var tint: Color

    static let current = [
        WorkflowStep(
            title: "Capture",
            detail: "Create a package from safe, reviewable providers.",
            systemImage: "camera.viewfinder",
            tint: .blue
        ),
        WorkflowStep(
            title: "Inspect",
            detail: "Review captured, excluded, warning, and user-action items.",
            systemImage: "doc.text.magnifyingglass",
            tint: .purple
        ),
        WorkflowStep(
            title: "Compare",
            detail: "Diff the package against the current Mac before planning changes.",
            systemImage: "square.split.2x1",
            tint: .indigo
        ),
        WorkflowStep(
            title: "Dry Run",
            detail: "Group install, configure, skip, blocked, and review-required work.",
            systemImage: "list.bullet.rectangle",
            tint: .orange
        ),
        WorkflowStep(
            title: "Apply",
            detail: "Use explicit confirmation for the small Finder-safe write path.",
            systemImage: "checkmark.shield",
            tint: .green
        )
    ]
}

private struct ActionItem: Identifiable {
    var id: String { title }
    var title: String
    var status: String
    var systemImage: String
}

private struct KeyValueRow: Identifiable {
    var id: String { label }
    var label: String
    var value: String
}

struct DiffGroup: Identifiable {
    var id: String { title }
    var title: String
    var detail: String
    var systemImage: String

    static let current = [
        DiffGroup(title: "Matching", detail: "Already aligned", systemImage: "equal.circle"),
        DiffGroup(title: "Changed", detail: "Needs review", systemImage: "arrow.triangle.2.circlepath"),
        DiffGroup(title: "Missing", detail: "Could be added", systemImage: "plus.circle"),
        DiffGroup(title: "Current Only", detail: "Present here only", systemImage: "minus.circle"),
        DiffGroup(title: "Skipped", detail: "Excluded by design", systemImage: "forward.end.circle"),
        DiffGroup(title: "Blocked", detail: "Unsupported or unsafe", systemImage: "xmark.octagon")
    ]
}
