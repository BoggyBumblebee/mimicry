import ArgumentParser
import Foundation
import MimicryCore

@main
struct MimicryCommand: AsyncParsableCommand {
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
            Apply.self
        ]
    )
}

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Inspect whether this Mac is ready for Mimicry workflows."
    )

    func run() async throws {
        print("Mimicry Doctor")
        print("==============")
        print("Status: Phase 1 scaffold only")
        print("No system checks have been implemented yet.")
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
        if let output {
            print("Snapshot output requested: \(output)")
        }
        print("Snapshot generation is not implemented in Phase 1.")
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
        let store = MimicryPackageStore()
        let package = try store.read(from: URL(fileURLWithPath: packagePath))
        print("Mimicry Snapshot")
        print("================")
        print("Schema version: \(package.snapshot.schemaVersion)")
        print("Mimicry version: \(package.snapshot.mimicryVersion)")
        print("Sections: \(package.snapshot.sections.count)")
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
        _ = try MimicryPackageStore().read(from: URL(fileURLWithPath: packagePath))
        print("Validation passed.")
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
        print("Diff is not implemented in Phase 1.")
        print("Snapshot: \(packagePath)")
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

    func run() async throws {
        print("Apply is not implemented in Phase 1.")
        print("Snapshot: \(packagePath)")
        print("Dry run: \(dryRun)")
    }
}
