import Darwin
import Foundation

public struct MacCapabilitySystemInfo: Equatable, Sendable {
    public var macOSVersion: String
    public var architecture: MacArchitecture
    public var hardwareModel: String
    public var hostname: String
    public var username: String
    public var iCloudDocumentsDirectoryExists: Bool
    public var appStoreApplicationExists: Bool

    public init(
        macOSVersion: String,
        architecture: MacArchitecture,
        hardwareModel: String,
        hostname: String,
        username: String,
        iCloudDocumentsDirectoryExists: Bool,
        appStoreApplicationExists: Bool
    ) {
        self.macOSVersion = macOSVersion
        self.architecture = architecture
        self.hardwareModel = hardwareModel
        self.hostname = hostname
        self.username = username
        self.iCloudDocumentsDirectoryExists = iCloudDocumentsDirectoryExists
        self.appStoreApplicationExists = appStoreApplicationExists
    }

    public static func current(fileManager: FileManager = .default) -> MacCapabilitySystemInfo {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let iCloudDocumentsPath = homeDirectory.appendingPathComponent("Library/Mobile Documents").path

        return MacCapabilitySystemInfo(
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: currentArchitecture(),
            hardwareModel: sysctlString("hw.model") ?? "unknown",
            hostname: ProcessInfo.processInfo.hostName,
            username: NSUserName(),
            iCloudDocumentsDirectoryExists: fileManager.fileExists(atPath: iCloudDocumentsPath),
            appStoreApplicationExists: fileManager.fileExists(atPath: "/System/Applications/App Store.app")
                || fileManager.fileExists(atPath: "/Applications/App Store.app")
        )
    }

    private static func currentArchitecture() -> MacArchitecture {
        #if arch(arm64)
        return .arm64
        #elseif arch(x86_64)
        return .x86_64
        #else
        return .unknown
        #endif
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }

        let bytes = buffer.prefix(while: { $0 != 0 }).map(UInt8.init)
        return String(decoding: bytes, as: UTF8.self).trimmedNilIfEmpty
    }
}

public struct MacCapabilitiesDetector: Sendable {
    private let runner: CommandRunner
    private let systemInfoProvider: @Sendable () -> MacCapabilitySystemInfo

    public init(
        runner: CommandRunner = ProcessCommandRunner(),
        systemInfoProvider: @escaping @Sendable () -> MacCapabilitySystemInfo = { .current() }
    ) {
        self.runner = runner
        self.systemInfoProvider = systemInfoProvider
    }

    public func detect() async -> MacCapabilities {
        let systemInfo = systemInfoProvider()

        let administratorPrivileges = await detectAdministratorPrivileges()
        let commandLineTools = await commandSucceeds("/usr/bin/xcode-select", ["-p"])
        let xcodeVersion = await detectXcodeVersion()
        let homebrew = await detectHomebrew()
        let mas = await commandSucceeds("/usr/bin/which", ["mas"])
        let sipState = await detectSIPState()
        let fileVaultState = await detectFileVaultState()
        let managementState = await detectManagementState()

        return MacCapabilities(
            macOSVersion: systemInfo.macOSVersion,
            architecture: systemInfo.architecture,
            hardwareModel: systemInfo.hardwareModel,
            hostname: systemInfo.hostname,
            username: systemInfo.username,
            hasAdministratorPrivileges: administratorPrivileges,
            fileVaultState: fileVaultState,
            sipState: sipState,
            hasCommandLineTools: commandLineTools,
            xcodeVersion: xcodeVersion,
            homebrew: homebrew,
            hasMAS: mas,
            iCloudState: systemInfo.iCloudDocumentsDirectoryExists ? .available : .requiresUserAction,
            appStoreState: systemInfo.appStoreApplicationExists ? .available : .unknown,
            managementState: managementState
        )
    }

    private func detectAdministratorPrivileges() async -> Bool {
        let result = await run("/usr/bin/id", ["-Gn"])
        guard result.exitCode == 0 else {
            return false
        }

        return result.standardOutput
            .split(whereSeparator: \.isWhitespace)
            .contains("admin")
    }

    private func detectXcodeVersion() async -> String? {
        let result = await run("/usr/bin/xcodebuild", ["-version"])
        guard result.exitCode == 0 else {
            return nil
        }

        return result.standardOutput
            .split(separator: "\n")
            .first
            .map(String.init)?
            .trimmedNilIfEmpty
    }

    private func detectHomebrew() async -> HomebrewCapability {
        let whichResult = await run("/usr/bin/which", ["brew"])
        guard whichResult.exitCode == 0 else {
            return HomebrewCapability()
        }

        let prefixResult = await run("/usr/bin/env", ["brew", "--prefix"])
        let versionResult = await run("/usr/bin/env", ["brew", "--version"])
        let prefix = prefixResult.exitCode == 0 ? prefixResult.standardOutput.trimmedNilIfEmpty : nil
        let version = versionResult.exitCode == 0
            ? versionResult.standardOutput.split(separator: "\n").first.map(String.init)?.trimmedNilIfEmpty
            : nil

        return HomebrewCapability(
            isInstalled: true,
            prefix: prefix,
            version: version,
            architecture: homebrewArchitecture(prefix: prefix)
        )
    }

    private func detectSIPState() async -> CapabilityState {
        let result = await run("/usr/bin/csrutil", ["status"])
        guard result.exitCode == 0 else {
            return .unknown
        }

        let output = result.combinedOutput.lowercased()
        if output.contains("enabled") {
            return .enabled
        }
        if output.contains("disabled") {
            return .disabled
        }
        return .unknown
    }

    private func detectFileVaultState() async -> CapabilityState {
        let result = await run("/usr/bin/fdesetup", ["status"])
        guard result.exitCode == 0 else {
            return .unknown
        }

        let output = result.combinedOutput.lowercased()
        if output.contains("filevault is on") {
            return .enabled
        }
        if output.contains("filevault is off") {
            return .disabled
        }
        return .unknown
    }

    private func detectManagementState() async -> CapabilityState {
        let result = await run("/usr/bin/profiles", ["status", "-type", "enrollment"])
        guard result.exitCode == 0 else {
            return .unknown
        }

        let output = result.combinedOutput.lowercased()
        if output.contains("mdm enrollment: yes") || output.contains("enrolled via dep: yes") {
            return .managed
        }
        if output.contains("mdm enrollment: no") || output.contains("enrolled via dep: no") {
            return .unavailable
        }
        return .unknown
    }

    private func commandSucceeds(_ executable: String, _ arguments: [String]) async -> Bool {
        await run(executable, arguments).exitCode == 0
    }

    private func run(_ executable: String, _ arguments: [String]) async -> CommandResult {
        do {
            return try await runner.run(
                executable: URL(fileURLWithPath: executable),
                arguments: arguments,
                environment: nil
            )
        } catch {
            return CommandResult(
                executable: executable,
                arguments: arguments,
                exitCode: 1,
                standardError: String(describing: error)
            )
        }
    }

    private func homebrewArchitecture(prefix: String?) -> MacArchitecture {
        switch prefix {
        case "/opt/homebrew":
            .arm64
        case "/usr/local":
            .x86_64
        default:
            .unknown
        }
    }
}

private extension CommandResult {
    var combinedOutput: String {
        [standardOutput, standardError].joined(separator: "\n")
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
