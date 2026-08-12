import Foundation
import MimicryCore

public enum MimicryCLIResponses {
    public static let phaseOneSubcommandNames = [
        "doctor",
        "snapshot",
        "inspect",
        "validate",
        "diff",
        "apply"
    ]

    public static func doctor() -> String {
        """
        Mimicry Doctor
        ==============
        Status: Phase 1 scaffold only
        No system checks have been implemented yet.
        """
    }

    public static func snapshot(output: String?) -> String {
        var lines: [String] = []
        if let output {
            lines.append("Snapshot output requested: \(output)")
        }
        lines.append("Snapshot generation is not implemented in Phase 1.")
        return lines.joined(separator: "\n")
    }

    public static func inspect(packagePath: String) throws -> String {
        let store = MimicryPackageStore()
        let package = try store.read(from: URL(fileURLWithPath: packagePath))
        return """
        Mimicry Snapshot
        ================
        Schema version: \(package.snapshot.schemaVersion)
        Mimicry version: \(package.snapshot.mimicryVersion)
        Sections: \(package.snapshot.sections.count)
        """
    }

    public static func validate(packagePath: String) throws -> String {
        _ = try MimicryPackageStore().read(from: URL(fileURLWithPath: packagePath))
        return "Validation passed."
    }

    public static func diff(packagePath: String) -> String {
        """
        Diff is not implemented in Phase 1.
        Snapshot: \(packagePath)
        """
    }

    public static func apply(packagePath: String, dryRun: Bool) -> String {
        """
        Apply is not implemented in Phase 1.
        Snapshot: \(packagePath)
        Dry run: \(dryRun)
        """
    }
}
