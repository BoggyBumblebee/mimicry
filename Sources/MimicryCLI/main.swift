import ArgumentParser
import Foundation
import MimicryCLISupport
import MimicryCore

@main
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct MimicryRootCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mimicry",
        abstract: "Snapshot, inspect, compare, and apply macOS configuration declarations.",
        version: "0.1.0",
        subcommands: [
            Doctor.self,
            Snapshot.self,
            Inspect.self,
            Validate.self,
            Diff.self,
            Apply.self,
            ExportBrowserBookmarks.self
        ]
    )
}

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Inspect whether this Mac is ready for Mimicry workflows."
    )

    func run() async throws {
        let capabilities = await MacCapabilitiesDetector().detect()
        print(MimicryCLIResponses.doctor(capabilities: capabilities))
    }
}

struct Snapshot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshot",
        abstract: "Create a Mimicry snapshot package."
    )

    @Option(name: .long, help: "Output .mimicry package path.")
    var output: String?

    func run() async throws {
        let outputURL = URL(fileURLWithPath: output ?? "mimicry-snapshot.mimicry")
            .standardizedFileURL
        let result = try await MimicrySnapshotBuilder().writeSnapshot(to: outputURL)
        print(MimicryCLIResponses.snapshot(package: result.package))
    }
}

struct Inspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect a Mimicry snapshot package."
    )

    @Argument(help: "Path to a .mimicry package.")
    var packagePath: String

    func run() async throws {
        print(try MimicryCLIResponses.inspect(packagePath: packagePath))
    }
}

struct Validate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate a Mimicry snapshot package."
    )

    @Argument(help: "Path to a .mimicry package.")
    var packagePath: String

    func run() async throws {
        print(try MimicryCLIResponses.validate(packagePath: packagePath))
    }
}

struct Diff: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diff",
        abstract: "Compare a snapshot to the current Mac."
    )

    @Argument(help: "Path to a .mimicry package.")
    var packagePath: String

    func run() async throws {
        let result = try await MimicrySnapshotBuilder().buildSnapshot()
        let currentSnapshot = result.snapshot
        print(try MimicryCLIResponses.diff(packagePath: packagePath, currentSnapshot: currentSnapshot))
    }
}

struct Apply: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apply",
        abstract: "Apply a Mimicry snapshot package."
    )

    @Argument(help: "Path to a .mimicry package.")
    var packagePath: String

    @Flag(help: "Plan actions without changing this Mac.")
    var dryRun = false

    @Flag(help: "Allow the first narrow Finder apply path to change this Mac.")
    var confirm = false

    func run() async throws {
        let currentSnapshot: MimicrySnapshot?
        if dryRun || confirm {
            let result = try await MimicrySnapshotBuilder().buildSnapshot()
            currentSnapshot = result.snapshot
        } else {
            currentSnapshot = nil
        }

        if confirm, !dryRun, let currentSnapshot {
            let package = try MimicryPackageStore().read(from: URL(fileURLWithPath: packagePath))
            let summary = try await FinderPreferenceApplyExecutor().apply(
                reference: package.snapshot,
                current: currentSnapshot
            )
            print(MimicryCLIResponses.confirmedApply(packagePath: packagePath, summary: summary))
        } else {
            print(try MimicryCLIResponses.apply(
                packagePath: packagePath,
                dryRun: dryRun,
                currentSnapshot: currentSnapshot
            ))
        }
    }
}

struct ExportBrowserBookmarks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export-browser-bookmarks",
        abstract: "Export sanitized browser bookmarks from a snapshot to an HTML import file."
    )

    @Argument(help: "Path to a .mimicry package.")
    var packagePath: String

    @Option(name: .long, help: "Output browser-importable HTML file path.")
    var output: String

    func run() async throws {
        print(try MimicryCLIResponses.exportBrowserBookmarks(
            packagePath: packagePath,
            outputPath: output
        ))
    }
}
