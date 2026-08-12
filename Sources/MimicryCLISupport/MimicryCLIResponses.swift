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

    public static func doctor(capabilities: MacCapabilities) -> String {
        let findings = DoctorFinding.findings(for: capabilities)
        let rows = findings.map { finding in
            "[\(finding.status.rawValue)] \(finding.title): \(finding.detail)"
        }

        return ([
            "Mimicry Doctor",
            "==============",
            "Host: \(capabilities.hostname)",
            "User: \(capabilities.username)",
            "macOS: \(capabilities.macOSVersion)",
            "Hardware: \(capabilities.hardwareModel)",
            "Architecture: \(capabilities.architecture.rawValue)",
            ""
        ] + rows + [
            "",
            "No system settings were changed."
        ]).joined(separator: "\n")
    }

    public static func snapshot(package: MimicryPackage) -> String {
        let warningCount = package.snapshot.sections.reduce(0) { count, section in
            count + section.warnings.count
        }

        return """
        Mimicry Snapshot Created
        ========================
        Package: \(package.url.path)
        Sections: \(package.snapshot.sections.count)
        Warnings: \(warningCount)
        No system settings were changed.
        """
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
        Diff is not implemented yet.
        Snapshot: \(packagePath)
        """
    }

    public static func apply(packagePath: String, dryRun: Bool) -> String {
        """
        Apply is not implemented yet.
        Snapshot: \(packagePath)
        Dry run: \(dryRun)
        """
    }
}

public struct DoctorFinding: Equatable, Sendable {
    public var status: DoctorFindingStatus
    public var title: String
    public var detail: String

    public init(status: DoctorFindingStatus, title: String, detail: String) {
        self.status = status
        self.title = title
        self.detail = detail
    }

    public static func findings(for capabilities: MacCapabilities) -> [DoctorFinding] {
        [
            DoctorFinding(
                status: .info,
                title: "macOS baseline",
                detail: "Mimicry is targeting macOS 15 and newer."
            ),
            DoctorFinding(
                status: capabilities.hasAdministratorPrivileges ? .pass : .warn,
                title: "Administrator access",
                detail: capabilities.hasAdministratorPrivileges
                    ? "Current user is in the admin group."
                    : "Some future apply actions may require an administrator account."
            ),
            DoctorFinding(
                status: capabilities.hasCommandLineTools ? .pass : .blocked,
                title: "Command Line Tools",
                detail: capabilities.hasCommandLineTools
                    ? "Xcode Command Line Tools are available."
                    : "Install Xcode Command Line Tools before provider detection."
            ),
            DoctorFinding(
                status: capabilities.xcodeVersion == nil ? .info : .pass,
                title: "Xcode",
                detail: capabilities.xcodeVersion ?? "Full Xcode was not detected; Command Line Tools may be enough for early workflows."
            ),
            DoctorFinding(
                status: capabilities.homebrew.isInstalled ? .pass : .warn,
                title: "Homebrew",
                detail: homebrewDetail(capabilities.homebrew)
            ),
            DoctorFinding(
                status: capabilities.hasMAS ? .pass : .warn,
                title: "mas CLI",
                detail: capabilities.hasMAS
                    ? "`mas` is available for App Store inventory."
                    : "`mas` is not available; App Store inventory will be limited until installed."
            ),
            DoctorFinding(
                status: stateStatus(capabilities.fileVaultState, available: .info, unavailable: .info),
                title: "FileVault",
                detail: stateDetail(capabilities.fileVaultState)
            ),
            DoctorFinding(
                status: stateStatus(capabilities.sipState, available: .pass, unavailable: .warn),
                title: "System Integrity Protection",
                detail: stateDetail(capabilities.sipState)
            ),
            DoctorFinding(
                status: stateStatus(capabilities.iCloudState, available: .info, unavailable: .info),
                title: "iCloud",
                detail: stateDetail(capabilities.iCloudState)
            ),
            DoctorFinding(
                status: stateStatus(capabilities.appStoreState, available: .info, unavailable: .info),
                title: "App Store",
                detail: stateDetail(capabilities.appStoreState)
            ),
            DoctorFinding(
                status: capabilities.managementState == .managed ? .warn : .info,
                title: "Device management",
                detail: stateDetail(capabilities.managementState)
            )
        ]
    }

    private static func homebrewDetail(_ homebrew: HomebrewCapability) -> String {
        guard homebrew.isInstalled else {
            return "Homebrew was not detected; Homebrew snapshots will be skipped."
        }

        var parts: [String] = []
        if let version = homebrew.version {
            parts.append(version)
        }
        if let prefix = homebrew.prefix {
            parts.append("prefix \(prefix)")
        }
        if homebrew.architecture != .unknown {
            parts.append("architecture \(homebrew.architecture.rawValue)")
        }

        return parts.isEmpty ? "Homebrew is available." : parts.joined(separator: ", ")
    }

    private static func stateStatus(
        _ state: CapabilityState,
        available: DoctorFindingStatus,
        unavailable: DoctorFindingStatus
    ) -> DoctorFindingStatus {
        switch state {
        case .available, .enabled:
            return available
        case .unavailable, .disabled, .unsupported:
            return unavailable
        case .managed, .requiresUserAction:
            return .warn
        case .unknown:
            return .info
        }
    }

    private static func stateDetail(_ state: CapabilityState) -> String {
        switch state {
        case .available:
            return "Available."
        case .unavailable:
            return "Not available."
        case .enabled:
            return "Enabled."
        case .disabled:
            return "Disabled."
        case .managed:
            return "Managed by organization policy."
        case .requiresUserAction:
            return "Requires user action or sign-in."
        case .unsupported:
            return "Unsupported on this Mac."
        case .unknown:
            return "State could not be determined."
        }
    }
}

public enum DoctorFindingStatus: String, Equatable, Sendable {
    case pass = "PASS"
    case warn = "WARN"
    case info = "INFO"
    case blocked = "BLOCKED"
}
