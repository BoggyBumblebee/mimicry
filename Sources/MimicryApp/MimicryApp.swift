import AppKit
import MimicryCore
import SwiftUI

@main
struct MimicryApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        .commands {
            SidebarCommands()
            PackageCommands(model: model)
        }

        Settings {
            SettingsView()
        }
    }
}

struct RootView: View {
    @ObservedObject private var model: AppModel
    @State private var selection: AppSection? = .snapshot

    init(model: AppModel = AppModel()) {
        self.model = model
    }

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection)
        } detail: {
            DetailView(section: selection ?? .snapshot, model: model)
        }
        .frame(minWidth: 980, minHeight: 660)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    selection = .snapshot
                    PackageActions.createSnapshot(model: model)
                } label: {
                    Label("Create Snapshot", systemImage: "camera.viewfinder")
                }
                .help("Create a .mimicry package")
                .disabled(model.snapshotState.isRunning)

                Button {
                    selection = .snapshot
                    PackageActions.openPackage(model: model)
                } label: {
                    Label("Open Package", systemImage: "folder")
                }
                .help("Open a .mimicry package")
                .disabled(model.packageState.isRunning)

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

private struct PackageCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandMenu("Package") {
            Button {
                PackageActions.createSnapshot(model: model)
            } label: {
                Label("Create Snapshot...", systemImage: "camera.viewfinder")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(model.snapshotState.isRunning)

            Button {
                PackageActions.openPackage(model: model)
            } label: {
                Label("Open Package...", systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(model.packageState.isRunning)
        }
    }
}

private enum PackageActions {
    @MainActor
    static func createSnapshot(model: AppModel) {
        guard let outputURL = SnapshotSavePanel.outputURL() else {
            return
        }

        Task {
            await model.createSnapshot(to: outputURL)
        }
    }

    @MainActor
    static func openPackage(model: AppModel) {
        guard let packageURL = PackageOpenPanel.packageURL() else {
            return
        }

        Task {
            await model.openPackage(at: packageURL)
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
                case .snapshot:
                    SnapshotView(model: model)
                case .apply:
                    ApplyView(model: model)
                case .compare:
                    CompareView(model: model)
                case .history:
                    HistoryView(model: model)
                case .diagnostics:
                    DiagnosticsView(model: model)
                }
            }
            .padding(28)
            .frame(maxWidth: section == .snapshot ? .infinity : 1120, alignment: .leading)
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

private struct SnapshotView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if shouldShowStartingContent {
            SnapshotStartingContentView()
        } else {
            PackageReviewView(snapshotState: model.snapshotState, packageState: model.packageState)
        }
    }

    private var shouldShowStartingContent: Bool {
        if case .idle = model.snapshotState, case .idle = model.packageState {
            return true
        }

        return false
    }
}

private struct SnapshotStartingContentView: View {
    private let providers = ProviderSummary.current
    private let workflow = WorkflowStep.current

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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

            ContentPanel(title: "Providers", systemImage: "square.stack.3d.up") {
                VStack(spacing: 0) {
                    ForEach(providers) { provider in
                        ProviderRow(provider: provider)
                        if provider.id != providers.last?.id {
                            Divider()
                                .padding(.leading, 36)
                        }
                    }
                }
            }
        }
    }
}

private struct ApplyView: View {
    @ObservedObject var model: AppModel
    @State private var isConfirmingApply = false

    var body: some View {
        TwoColumnPanels {
            ContentPanel(title: "Package", systemImage: "doc.text.magnifyingglass") {
                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        Task {
                            await model.planApplyForCurrentPackage()
                        }
                    } label: {
                        Label("Dry Run", systemImage: "checklist")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canPlanApply)

                    PackageInspectView(state: model.packageState)
                }
            }

            ContentPanel(title: "Dry Run Plan", systemImage: "checklist") {
                ApplyPlanResultView(state: model.applyPlanState)
            }

            ContentPanel(title: "Confirmed Apply", systemImage: "checkmark.shield") {
                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        isConfirmingApply = true
                    } label: {
                        Label("Apply Finder", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canConfirmedApply)
                    .confirmationDialog(
                        "Apply Finder-safe preferences?",
                        isPresented: $isConfirmingApply,
                        titleVisibility: .visible
                    ) {
                        Button("Apply Finder", role: .destructive) {
                            Task {
                                await model.confirmedApplyForCurrentPackage()
                            }
                        }
                        Button("Cancel", role: .cancel) {
                            isConfirmingApply = false
                        }
                    } message: {
                        Text("Only explicitly safe Finder boolean and string preferences are considered. A backup is written before any change.")
                    }

                    ConfirmedApplyResultView(state: model.confirmedApplyState, canApply: canConfirmedApply)
                }
            }

            ContentPanel(title: "Browser Handoff", systemImage: "safari") {
                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        guard let outputURL = BrowserBookmarkSavePanel.outputURL(packageURL: currentPackageURL) else {
                            return
                        }
                        Task {
                            await model.exportBrowserBookmarksForCurrentPackage(to: outputURL)
                        }
                    } label: {
                        Label("Export HTML...", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canExportBrowserBookmarks)

                    BrowserBookmarkExportResultView(state: model.browserBookmarkExportState)
                }
            }
        }
    }

    private var canPlanApply: Bool {
        guard !model.applyPlanState.isRunning else {
            return false
        }

        if case .succeeded = model.packageState {
            return true
        }

        return false
    }

    private var canExportBrowserBookmarks: Bool {
        guard !model.browserBookmarkExportState.isRunning else {
            return false
        }

        return currentPackageURL != nil
    }

    private var canConfirmedApply: Bool {
        guard !model.confirmedApplyState.isRunning else {
            return false
        }
        guard let currentPackageURL else {
            return false
        }
        guard case let .succeeded(plan) = model.applyPlanState else {
            return false
        }

        return plan.packageURL == currentPackageURL
    }

    private var currentPackageURL: URL? {
        guard case let .succeeded(package) = model.packageState else {
            return nil
        }

        return package.url
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

            ContentPanel(title: "Audit Log", systemImage: "list.bullet.rectangle") {
                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        guard let outputURL = AuditLogSavePanel.outputURL() else {
                            return
                        }
                        model.exportAuditLog(to: outputURL)
                    } label: {
                        Label("Export JSON...", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.auditLog.isEmpty || model.auditExportState.isRunning)

                    AuditLogExportResultView(state: model.auditExportState, entries: model.auditLog)
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

private struct ProviderRow: View {
    var provider: ProviderSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: provider.systemImage)
                .frame(width: 24)
                .foregroundStyle(provider.tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(provider.title)
                    .font(.subheadline.weight(.semibold))
                Text(provider.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.vertical, 10)
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

struct PackageReviewView: View {
    var snapshotState: AppCommandState<AppSnapshotSummary>
    var packageState: AppCommandState<AppPackageSummary>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if snapshotState.isRunning {
                ProgressRow(title: "Creating snapshot", detail: "No system settings are being changed.")
            } else if shouldShowSnapshotFailure, case let .failed(message) = snapshotState {
                FailureRow(title: "Snapshot failed", detail: message)
            } else {
                PackageInspectView(state: packageState)
            }
        }
    }

    private var shouldShowSnapshotFailure: Bool {
        guard case .failed = snapshotState else {
            return false
        }

        if case .idle = packageState {
            return true
        }

        return false
    }
}

struct PackageInspectView: View {
    var state: AppCommandState<AppPackageSummary>

    var body: some View {
        switch state {
        case .idle:
            EmptyStateRow(title: "No package open", detail: "Open a .mimicry package to inspect its contents.", systemImage: "doc")
        case .running:
            ProgressRow(title: "Opening package", detail: "Validating manifest and checksums.")
        case let .succeeded(summary):
            PackageDocumentReview(summary: summary)
        case let .failed(message):
            FailureRow(title: "Package could not be opened", detail: message)
        }
    }
}

struct PackageDocumentReview: View {
    var summary: AppPackageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PackageDocumentHeader(summary: summary)

            PackageStatusStrip(summary: summary)

            if !summary.sections.isEmpty {
                PackageOutlineView(sections: summary.sections)
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([summary.url])
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct PackageDocumentHeader: View {
    var summary: AppPackageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(summary.packageName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(summary.warningCount == 1 ? "1 warning" : "\(summary.warningCount) warnings")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(summary.warningCount > 0 ? .orange : .secondary)
            }

            HStack(spacing: 6) {
                PackageHeaderMetadata("Source", summary.source)
                PackageHeaderSeparator()
                PackageHeaderMetadata("macOS", summary.macOSVersion)
                PackageHeaderSeparator()
                PackageHeaderMetadata("Architecture", summary.architecture)
                PackageHeaderSeparator()
                PackageHeaderMetadata("Sections", "\(summary.sectionCount)")
                PackageHeaderSeparator()
                PackageHeaderMetadata("Items", "\(summary.itemCount)")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        .padding(.bottom, 2)
    }
}

private struct PackageHeaderMetadata: View {
    var label: String
    var value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        Text("\(label): \(value)")
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

private struct PackageHeaderSeparator: View {
    var body: some View {
        Text("/")
            .foregroundStyle(.tertiary)
    }
}

struct PackageStatusStrip: View {
    var summary: AppPackageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                PackageStatusPill(title: "Safe", value: summary.safeCount, systemImage: "checkmark.circle", tint: .green)
                PackageStatusPill(title: "Review", value: summary.reviewCount, systemImage: "person.crop.circle.badge.exclamationmark", tint: .orange)
                PackageStatusPill(title: "Excluded", value: summary.excludedCount, systemImage: "forward.end.circle", tint: .secondary)
                PackageStatusPill(title: "Unsupported", value: summary.unsupportedCount, systemImage: "xmark.octagon", tint: .red)
            }

            if summary.compatibility.hasConstrainedItems {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    PackageStatusPill(title: "Managed", value: summary.compatibility.managedCount, systemImage: "lock.shield", tint: .secondary)
                    PackageStatusPill(title: "Machine", value: summary.compatibility.machineSpecificCount, systemImage: "desktopcomputer", tint: .blue)
                    PackageStatusPill(title: "Hardware", value: summary.compatibility.hardwareSpecificCount, systemImage: "cpu", tint: .secondary)
                    PackageStatusPill(title: "User", value: summary.compatibility.userSpecificCount, systemImage: "person.crop.circle", tint: .secondary)
                    PackageStatusPill(title: "Unsupported", value: summary.compatibility.unsupportedCount, systemImage: "xmark.octagon", tint: .red)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 112), spacing: 8, alignment: .leading)]
    }
}

private struct PackageStatusPill: View {
    var title: String
    var value: Int
    var systemImage: String
    var tint: AppDisplayTint

    var body: some View {
        Label {
            Text("\(title) \(value)")
                .font(.callout)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundStyle(tint.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quinary, in: Capsule())
    }
}

struct PackageOutlineView: View {
    var sections: [PackageSectionSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sections) { section in
                PackageSectionDisclosure(section: section)
                if section.id != sections.last?.id {
                    Divider()
                        .padding(.leading, 34)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        }
    }
}

private struct PackageSectionDisclosure: View {
    var section: PackageSectionSummary

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                if !section.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(section.warnings) { warning in
                            PackageWarningRow(warning: warning)
                        }
                    }
                }

                if !section.itemGroups.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(section.itemGroups) { group in
                            PackageItemGroupDisclosure(group: group)
                        }
                    }
                } else if !section.items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(section.items) { item in
                            PackageItemRow(item: item)
                        }
                    }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 4)
            .padding(.leading, 30)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 24)
                    .foregroundStyle(.secondary)
                Text(section.name)
                    .font(.body.weight(.semibold))
                Spacer()
                Text("\(section.itemCount) items")
                    .foregroundStyle(.secondary)
                if section.warningCount > 0 {
                    Text("\(section.warningCount) warnings")
                        .foregroundStyle(.orange)
                }
            }
            .font(.callout)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
    }
}

private struct PackageItemGroupDisclosure: View {
    var group: PackageItemGroupSummary

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.items) { item in
                    PackageItemRow(item: item)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 2)
            .padding(.leading, 30)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: group.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 24)
                    .foregroundStyle(.secondary)
                Text(group.title)
                    .font(.body.weight(.medium))
                Spacer()
                Text("\(group.items.count) items")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.vertical, 6)
        }
    }
}

private struct PackageWarningRow: View {
    var warning: PackageWarningSummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(warning.code)
                    .font(.callout.weight(.semibold))
                Text(warning.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct PackageItemRow: View {
    var item: PackageItemSummary

    var body: some View {
        let display = PackageItemDisplay(item: item)

        HStack(alignment: .top, spacing: 10) {
            Image(systemName: display.iconName)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24)
                .foregroundStyle(display.tint.color)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.key)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(item.value)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 16)

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(display.statusLabel)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(display.tint.color)
                        Text(display.detailLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 5)
    }
}

struct PackageItemDisplay: Equatable {
    var iconName: String
    var tint: AppDisplayTint
    var statusLabel: String
    var detailLabel: String

    init(iconName: String, tint: AppDisplayTint, statusLabel: String, detailLabel: String) {
        self.iconName = iconName
        self.tint = tint
        self.statusLabel = statusLabel
        self.detailLabel = detailLabel
    }

    init(item: PackageItemSummary) {
        if item.isInformationalOnly {
            iconName = "info.circle"
            tint = .blue
            statusLabel = "Not Applied"
            detailLabel = "\(item.classification), \(item.applicability)"
            return
        }

        switch item.classification {
        case "Safe Configuration":
            iconName = "checkmark.circle"
            tint = .green
        case "Unsupported":
            iconName = "xmark.octagon"
            tint = .red
        case "Excluded":
            iconName = "forward.end.circle"
            tint = .secondary
        default:
            iconName = "person.crop.circle.badge.exclamationmark"
            tint = .orange
        }

        statusLabel = item.classification
        detailLabel = item.applicability
    }
}

enum AppDisplayTint: Equatable {
    case green
    case red
    case secondary
    case orange
    case blue

    var color: Color {
        switch self {
        case .green:
            return .green
        case .red:
            return .red
        case .secondary:
            return .secondary
        case .orange:
            return .orange
        case .blue:
            return .blue
        }
    }
}

struct CompareResultView: View {
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

struct ApplyPlanResultView: View {
    var state: AppCommandState<AppApplyPlanSummary>

    var body: some View {
        switch state {
        case .idle:
            VStack(alignment: .leading, spacing: 14) {
                EmptyStateRow(title: "No dry run yet", detail: "Open a package and preview the apply plan.", systemImage: "checklist")
                ApplyGroupGrid(summary: nil)
            }
        case .running:
            ProgressRow(title: "Planning apply", detail: "Comparing the package with this Mac without changing settings.")
        case let .succeeded(summary):
            VStack(alignment: .leading, spacing: 14) {
                KeyValueList(rows: [
                    KeyValueRow(label: "Package", value: summary.packageURL.lastPathComponent),
                    KeyValueRow(label: "Reference", value: summary.referenceSource),
                    KeyValueRow(label: "Current", value: summary.currentSource),
                    KeyValueRow(label: "Actions", value: "\(summary.actionCount)")
                ])

                ApplyGroupGrid(summary: summary)

                CompatibilitySummaryView(summary: summary.compatibility)

                if summary.groups.isEmpty {
                    EmptyStateRow(title: "No actions required", detail: "The dry-run planner found no changes to apply.", systemImage: "checkmark.circle")
                } else {
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(summary.groups) { group in
                            ApplyActionGroupView(group: group)
                        }
                    }
                }
            }
        case let .failed(message):
            FailureRow(title: "Dry run failed", detail: message)
        }
    }
}

private struct ApplyGroupGrid: View {
    var summary: AppApplyPlanSummary?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
            CompactStatusTile(title: "Install", value: value(\.installCount), systemImage: "arrow.down.circle")
            CompactStatusTile(title: "Configure", value: value(\.configureCount), systemImage: "switch.2")
            CompactStatusTile(title: "Skip", value: value(\.skipCount), systemImage: "forward.end.circle")
            CompactStatusTile(title: "Blocked", value: value(\.blockedCount), systemImage: "xmark.octagon")
            CompactStatusTile(title: "User Action", value: value(\.userActionCount), systemImage: "person.crop.circle.badge.exclamationmark")
        }
    }

    private func value(_ keyPath: KeyPath<AppApplyPlanSummary, Int>) -> String {
        guard let summary else {
            return "-"
        }

        return "\(summary[keyPath: keyPath])"
    }
}

private struct CompatibilitySummaryView: View {
    var summary: AppCompatibilitySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if summary.hasConstrainedItems {
                EmptyStateRow(
                    title: "Compatibility review needed",
                    detail: "Managed, machine-specific, hardware-specific, user-specific, or unsupported items need review before apply.",
                    systemImage: "lock.shield"
                )
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                CompactStatusTile(title: "Managed", value: "\(summary.managedCount)", systemImage: "lock.shield")
                CompactStatusTile(title: "Machine", value: "\(summary.machineSpecificCount)", systemImage: "desktopcomputer")
                CompactStatusTile(title: "Hardware", value: "\(summary.hardwareSpecificCount)", systemImage: "cpu")
                CompactStatusTile(title: "User", value: "\(summary.userSpecificCount)", systemImage: "person.crop.circle")
                CompactStatusTile(title: "Unsupported", value: "\(summary.unsupportedCount)", systemImage: "xmark.octagon")
            }
        }
    }
}

private struct ApplyActionGroupView: View {
    var group: ApplyActionGroupSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(group.actionCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.actions.prefix(4)) { action in
                    ApplyActionRow(action: action)
                }

                if group.actions.count > 4 {
                    Text("\(group.actions.count - 4) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ApplyActionRow: View {
    var action: AppPlannedActionSummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: action.requiresElevation ? "lock.shield" : "checklist")
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.provider)
                    .font(.subheadline.weight(.semibold))
                Text(action.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}

struct BrowserBookmarkExportResultView: View {
    var state: AppCommandState<AppBrowserBookmarkExportSummary>

    var body: some View {
        switch state {
        case .idle:
            EmptyStateRow(
                title: "No browser export yet",
                detail: "Write a reviewable HTML import file from captured browser bookmarks.",
                systemImage: "safari"
            )
        case .running:
            ProgressRow(title: "Exporting browser bookmarks", detail: "Writing an HTML handoff without touching browser profiles.")
        case let .succeeded(summary):
            VStack(alignment: .leading, spacing: 14) {
                KeyValueList(rows: [
                    KeyValueRow(label: "Package", value: summary.packageURL.lastPathComponent),
                    KeyValueRow(label: "Output", value: summary.outputURL.lastPathComponent),
                    KeyValueRow(label: "Browser sections", value: "\(summary.browserSectionCount)"),
                    KeyValueRow(label: "Bookmarks exported", value: "\(summary.exportedBookmarkCount)"),
                    KeyValueRow(label: "Duplicates skipped", value: "\(summary.skippedDuplicateCount)"),
                    KeyValueRow(label: "Invalid URLs skipped", value: "\(summary.skippedInvalidCount)"),
                    KeyValueRow(label: "Unavailable skipped", value: "\(summary.skippedUnavailableSourceCount)")
                ])

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([summary.outputURL])
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
            }
        case let .failed(message):
            FailureRow(title: "Browser export failed", detail: message)
        }
    }
}

struct ConfirmedApplyResultView: View {
    var state: AppCommandState<AppConfirmedApplySummary>
    var canApply: Bool

    var body: some View {
        switch state {
        case .idle:
            EmptyStateRow(
                title: canApply ? "Ready for confirmed apply" : "Dry run required",
                detail: canApply
                    ? "Finder-safe preferences can be applied with explicit confirmation."
                    : "Open a package and run a dry run before applying Finder preferences.",
                systemImage: canApply ? "checkmark.shield" : "shield"
            )
        case .running:
            ProgressRow(title: "Applying Finder preferences", detail: "Writing only backed-up Finder-safe settings.")
        case let .succeeded(summary):
            VStack(alignment: .leading, spacing: 14) {
                KeyValueList(rows: [
                    KeyValueRow(label: "Package", value: summary.packageURL.lastPathComponent),
                    KeyValueRow(label: "Backup", value: summary.backupURL?.lastPathComponent ?? "Not needed"),
                    KeyValueRow(label: "Results", value: "\(summary.resultCount)"),
                    KeyValueRow(label: "Applied", value: "\(summary.appliedCount)"),
                    KeyValueRow(label: "Warnings", value: "\(summary.warningCount)"),
                    KeyValueRow(label: "Skipped", value: "\(summary.skippedCount)"),
                    KeyValueRow(label: "Failed", value: "\(summary.failedCount)")
                ])

                if summary.results.isEmpty {
                    EmptyStateRow(
                        title: "No Finder changes required",
                        detail: "The confirmed apply path found no safe Finder preference changes.",
                        systemImage: "checkmark.circle"
                    )
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(summary.results.prefix(4)) { result in
                            ApplyResultRow(result: result)
                        }

                        if summary.results.count > 4 {
                            Text("\(summary.results.count - 4) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        case let .failed(message):
            FailureRow(title: "Confirmed apply failed", detail: message)
        }
    }
}

struct AuditLogExportResultView: View {
    var state: AppCommandState<AppAuditExportSummary>
    var entries: [AppAuditLogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch state {
            case .idle:
                if entries.isEmpty {
                    EmptyStateRow(
                        title: "No audit entries yet",
                        detail: "Snapshot, dry-run, confirmed apply, and browser handoff activity will appear here.",
                        systemImage: "list.bullet.rectangle"
                    )
                } else {
                    KeyValueList(rows: [
                        KeyValueRow(label: "Entries", value: "\(entries.count)"),
                        KeyValueRow(label: "Latest", value: entries.first?.operation.displayName ?? "None")
                    ])
                }
            case .running:
                ProgressRow(title: "Exporting audit log", detail: "Writing structured JSON for review.")
            case let .succeeded(summary):
                VStack(alignment: .leading, spacing: 14) {
                    KeyValueList(rows: [
                        KeyValueRow(label: "Output", value: summary.outputURL.lastPathComponent),
                        KeyValueRow(label: "Entries", value: "\(summary.entryCount)")
                    ])

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([summary.outputURL])
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                }
            case let .failed(message):
                FailureRow(title: "Audit export failed", detail: message)
            }

            if !entries.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entries.prefix(4)) { entry in
                        AuditLogRow(entry: entry)
                    }

                    if entries.count > 4 {
                        Text("\(entries.count - 4) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct AuditLogRow: View {
    var entry: AppAuditLogEntry

    var body: some View {
        let display = AuditLogEntryDisplay(entry: entry)

        HStack(alignment: .top, spacing: 10) {
            Image(systemName: display.iconName)
                .frame(width: 22)
                .foregroundStyle(display.tint.color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(entry.operation.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(entry.status.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(display.tint.color)
                }
                Text(entry.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let packageURL = entry.packageURL {
                    Text(packageURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
        }
    }
}

struct AuditLogEntryDisplay: Equatable {
    var iconName: String
    var tint: AppDisplayTint

    init(iconName: String, tint: AppDisplayTint) {
        self.iconName = iconName
        self.tint = tint
    }

    init(entry: AppAuditLogEntry) {
        switch entry.status {
        case "success":
            iconName = "checkmark.circle"
            tint = .green
        case "blocked", "warning":
            iconName = "exclamationmark.triangle"
            tint = .orange
        case "failed":
            iconName = "xmark.octagon"
            tint = .red
        default:
            iconName = "info.circle"
            tint = .secondary
        }
    }
}

private struct ApplyResultRow: View {
    var result: AppApplyResultSummary

    var body: some View {
        let display = ApplyResultDisplay(result: result)

        HStack(alignment: .top, spacing: 10) {
            Image(systemName: display.iconName)
                .frame(width: 22)
                .foregroundStyle(display.tint.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.status.capitalized)
                    .font(.subheadline.weight(.semibold))
                Text(result.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}

struct ApplyResultDisplay: Equatable {
    var iconName: String
    var tint: AppDisplayTint

    init(iconName: String, tint: AppDisplayTint) {
        self.iconName = iconName
        self.tint = tint
    }

    init(result: AppApplyResultSummary) {
        if result.status == "success" {
            iconName = "checkmark.circle"
            tint = .green
        } else {
            iconName = "exclamationmark.triangle"
            tint = .orange
        }
    }
}

struct DiagnosticsResultView: View {
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
                    KeyValueRow(label: "Architecture", value: summary.architecture),
                    KeyValueRow(label: "Management Review", value: summary.managementDetail)
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

private enum BrowserBookmarkSavePanel {
    @MainActor
    static func outputURL(packageURL: URL?) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mimicry-browser-bookmarks.html"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export Browser Bookmarks"
        panel.prompt = "Export"
        panel.directoryURL = packageURL?.deletingLastPathComponent()

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        if url.pathExtension == "html" {
            return url
        }

        return url.deletingPathExtension().appendingPathExtension("html")
    }
}

private enum AuditLogSavePanel {
    @MainActor
    static func outputURL() -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mimicry-audit-log.json"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export Mimicry Audit Log"
        panel.prompt = "Export"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        if url.pathExtension == "json" {
            return url
        }

        return url.deletingPathExtension().appendingPathExtension("json")
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case snapshot
    case apply
    case compare
    case history
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
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
        case .snapshot:
            "Review the open package contents."
        case .apply:
            "Plan changes first, then apply only the approved safe slice."
        case .compare:
            "Compare a package with the current Mac."
        case .history:
            "Track package activity and audit exports."
        case .diagnostics:
            "Check local tools and services."
        }
    }

    var systemImage: String {
        switch self {
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

struct ProviderSummary: Identifiable {
    var id: String { title }
    var title: String
    var detail: String
    var systemImage: String
    var tint: Color

    static let current = [
        ProviderSummary(
            title: "Environment",
            detail: "Records macOS version, architecture, hardware model, host, and local tool availability.",
            systemImage: "macbook",
            tint: .blue
        ),
        ProviderSummary(
            title: "Homebrew",
            detail: "Captures installed formulae and casks for review before any install planning.",
            systemImage: "shippingbox",
            tint: .teal
        ),
        ProviderSummary(
            title: "App Store",
            detail: "Captures Mac App Store application inventory when the local `mas` tool is available.",
            systemImage: "bag",
            tint: .pink
        ),
        ProviderSummary(
            title: "Finder",
            detail: "Captures selected Finder preferences and is the only provider with a confirmed safe write path today.",
            systemImage: "folder",
            tint: .green
        ),
        ProviderSummary(
            title: "Terminal",
            detail: "Captures shell and configuration-file metadata while redacting or excluding likely secrets.",
            systemImage: "terminal",
            tint: .secondary
        ),
        ProviderSummary(
            title: "iCloud",
            detail: "Reports local iCloud signals and marks account-specific settings for user review.",
            systemImage: "icloud",
            tint: .cyan
        ),
        ProviderSummary(
            title: "Safari",
            detail: "Captures bookmark structure for review and browser import handoff, without changing profiles.",
            systemImage: "safari",
            tint: .orange
        ),
        ProviderSummary(
            title: "Chrome",
            detail: "Captures bookmark metadata across Chrome profiles, redacting URL query and fragment details.",
            systemImage: "globe",
            tint: .red
        ),
        ProviderSummary(
            title: "Firefox",
            detail: "Captures bookmark metadata across Firefox profiles when profile databases are readable.",
            systemImage: "flame",
            tint: .purple
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
            title: "Snapshot: Capture",
            detail: "Create a `.mimicry` package from the providers listed below.",
            systemImage: "camera.viewfinder",
            tint: .blue
        ),
        WorkflowStep(
            title: "Snapshot: Inspect",
            detail: "Open the package review and expand sections to read items and warnings.",
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
            title: "Apply: Dry Run",
            detail: "Group install, configure, skip, blocked, and review-required work before mutation.",
            systemImage: "list.bullet.rectangle",
            tint: .orange
        ),
        WorkflowStep(
            title: "Apply: Confirm",
            detail: "Use explicit confirmation for the small Finder-safe write path.",
            systemImage: "checkmark.shield",
            tint: .green
        )
    ]
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
