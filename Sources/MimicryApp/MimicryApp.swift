import MimicryCore
import SwiftUI

@main
struct MimicryApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

private struct RootView: View {
    @State private var selection: AppSection? = .snapshot

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Mimicry")
        } detail: {
            DetailView(section: selection ?? .snapshot)
        }
        .frame(minWidth: 920, minHeight: 620)
    }
}

private struct DetailView: View {
    var section: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(section.title, systemImage: section.systemImage)
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text(section.phaseOneStatus)
                .foregroundStyle(.secondary)

            Divider()

            Text("Phase 1 is scaffolding the app shell, CLI, shared models, and snapshot package format. No system settings are changed by this build.")
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(28)
        .navigationTitle(section.title)
    }
}

private enum AppSection: String, CaseIterable, Identifiable {
    case snapshot
    case apply
    case compare
    case history
    case settings
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
        case .settings:
            "Settings"
        case .diagnostics:
            "Diagnostics"
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
        case .settings:
            "gearshape"
        case .diagnostics:
            "stethoscope"
        }
    }

    var phaseOneStatus: String {
        switch self {
        case .snapshot:
            "Create and inspect .mimicry package scaffolds."
        case .apply:
            "Apply planning is placeholder-only in Phase 1."
        case .compare:
            "Diff planning arrives after provider snapshots exist."
        case .history:
            "History will be backed by structured operation logs."
        case .settings:
            "Settings will hold safety, export, and CLI installation preferences."
        case .diagnostics:
            "Doctor checks arrive with the capability-detection provider."
        }
    }
}
