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

    public static func current(
        fileManager: FileManager = .default,
        paths: MacCapabilityPaths = .macOSDefault
    ) -> MacCapabilitySystemInfo {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let iCloudDocumentsPath = paths.applications.iCloudDocumentsURL(relativeTo: homeDirectory).path

        return MacCapabilitySystemInfo(
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: currentArchitecture(),
            hardwareModel: sysctlString("hw.model") ?? "unknown",
            hostname: ProcessInfo.processInfo.hostName,
            username: NSUserName(),
            iCloudDocumentsDirectoryExists: fileManager.fileExists(atPath: iCloudDocumentsPath),
            appStoreApplicationExists: paths.applications.appStoreApplicationLocations.contains { url in
                fileManager.fileExists(atPath: url.path)
            }
        )
    }

    public static func current(fileManager: FileManager = .default) -> MacCapabilitySystemInfo {
        current(fileManager: fileManager, paths: .macOSDefault)
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
    private let paths: MacCapabilityPaths
    private let systemInfoProvider: @Sendable () -> MacCapabilitySystemInfo

    public init(
        runner: CommandRunner = ProcessCommandRunner(),
        paths: MacCapabilityPaths = .macOSDefault
    ) {
        self.runner = runner
        self.paths = paths
        self.systemInfoProvider = { .current(paths: paths) }
    }

    public init(
        runner: CommandRunner = ProcessCommandRunner(),
        paths: MacCapabilityPaths,
        systemInfoProvider: @escaping @Sendable () -> MacCapabilitySystemInfo
    ) {
        self.runner = runner
        self.paths = paths
        self.systemInfoProvider = systemInfoProvider
    }

    public init(
        runner: CommandRunner = ProcessCommandRunner(),
        systemInfoProvider: @escaping @Sendable () -> MacCapabilitySystemInfo
    ) {
        self.init(
            runner: runner,
            paths: .macOSDefault,
            systemInfoProvider: systemInfoProvider
        )
    }

    public func detect() async -> MacCapabilities {
        let systemInfo = systemInfoProvider()

        let administratorPrivileges = await detectAdministratorPrivileges()
        let commandLineTools = await commandSucceeds(paths.developerTools.xcodeSelect, ["-p"])
        let xcodeVersion = await detectXcodeVersion()
        let homebrew = await detectHomebrew()
        let mas = await commandSucceeds(paths.shellTools.which, ["mas"])
        let sipState = await detectSIPState()
        let fileVaultState = await detectFileVaultState()
        let managementState = await detectManagementState()

        return MacCapabilities(
            environment: MacEnvironment(
                macOSVersion: systemInfo.macOSVersion,
                architecture: systemInfo.architecture,
                hardwareModel: systemInfo.hardwareModel,
                hostname: systemInfo.hostname,
                username: systemInfo.username
            ),
            security: MacSecurityCapabilities(
                hasAdministratorPrivileges: administratorPrivileges,
                fileVaultState: fileVaultState,
                sipState: sipState
            ),
            tools: MacToolCapabilities(
                hasCommandLineTools: commandLineTools,
                xcodeVersion: xcodeVersion,
                homebrew: homebrew,
                hasMAS: mas
            ),
            services: MacServiceCapabilities(
                iCloudState: systemInfo.iCloudDocumentsDirectoryExists ? .available : .requiresUserAction,
                appStoreState: systemInfo.appStoreApplicationExists ? .available : .unknown,
                managementState: managementState
            )
        )
    }

    private func detectAdministratorPrivileges() async -> Bool {
        let result = await run(paths.shellTools.id, ["-Gn"])
        guard result.exitCode == 0 else {
            return false
        }

        return result.standardOutput
            .split(whereSeparator: { $0.isWhitespace })
            .contains("admin")
    }

    private func detectXcodeVersion() async -> String? {
        let result = await run(paths.developerTools.xcodebuild, ["-version"])
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
        guard let command = await resolveHomebrew() else {
            return HomebrewCapability()
        }

        let versionResult = await command.run(["--version"], runner: runner)
        let prefix = command.prefixResult.standardOutput.trimmedNilIfEmpty
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

    private func resolveHomebrew() async -> ResolvedHomebrewCommand? {
        let whichResult = await run(paths.shellTools.which, ["brew"])
        if whichResult.exitCode == 0 {
            let prefixResult = await run(paths.shellTools.env, ["brew", "--prefix"])
            if prefixResult.exitCode == 0 {
                return ResolvedHomebrewCommand(
                    executable: paths.shellTools.env,
                    argumentPrefix: ["brew"],
                    prefixResult: prefixResult
                )
            }
        }

        for candidate in paths.homebrewPrefixes.executableCandidates {
            let prefixResult = await run(candidate, ["--prefix"])
            if prefixResult.exitCode == 0 {
                return ResolvedHomebrewCommand(
                    executable: candidate,
                    argumentPrefix: [],
                    prefixResult: prefixResult
                )
            }
        }

        return nil
    }

    private func detectSIPState() async -> CapabilityState {
        let result = await run(paths.securityTools.csrutil, ["status"])
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
        let result = await run(paths.securityTools.fdesetup, ["status"])
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
        let result = await run(paths.securityTools.profiles, ["status", "-type", "enrollment"])
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

    private func commandSucceeds(_ executable: URL, _ arguments: [String]) async -> Bool {
        await run(executable, arguments).exitCode == 0
    }

    private func run(_ executable: URL, _ arguments: [String]) async -> CommandResult {
        do {
            return try await runner.run(
                executable: executable,
                arguments: arguments,
                environment: nil
            )
        } catch {
            return CommandResult(
                executable: executable.path,
                arguments: arguments,
                exitCode: 1,
                standardError: String(describing: error)
            )
        }
    }

    private func homebrewArchitecture(prefix: String?) -> MacArchitecture {
        switch prefix {
        case paths.homebrewPrefixes.appleSilicon.path:
            .arm64
        case paths.homebrewPrefixes.intel.path:
            .x86_64
        default:
            .unknown
        }
    }
}

public struct MacCapabilityPaths: Equatable, Sendable {
    public var developerTools: MacCapabilityDeveloperToolPaths
    public var shellTools: MacCapabilityShellToolPaths
    public var securityTools: MacCapabilitySecurityToolPaths
    public var applications: MacCapabilityApplicationPaths
    public var homebrewPrefixes: MacCapabilityHomebrewPrefixes

    public init(
        developerTools: MacCapabilityDeveloperToolPaths = .macOSDefault,
        shellTools: MacCapabilityShellToolPaths = .macOSDefault,
        securityTools: MacCapabilitySecurityToolPaths = .macOSDefault,
        applications: MacCapabilityApplicationPaths = .macOSDefault,
        homebrewPrefixes: MacCapabilityHomebrewPrefixes = .macOSDefault
    ) {
        self.developerTools = developerTools
        self.shellTools = shellTools
        self.securityTools = securityTools
        self.applications = applications
        self.homebrewPrefixes = homebrewPrefixes
    }

    public static let macOSDefault = MacCapabilityPaths()
}

public struct MacCapabilityDeveloperToolPaths: Equatable, Sendable {
    public var xcodeSelect: URL
    public var xcodebuild: URL

    public init(
        xcodeSelect: URL? = nil,
        xcodebuild: URL? = nil
    ) {
        self.xcodeSelect = xcodeSelect ?? SystemToolPathFactory.usrBin("xcode-select")
        self.xcodebuild = xcodebuild ?? SystemToolPathFactory.usrBin("xcodebuild")
    }

    public static let macOSDefault = MacCapabilityDeveloperToolPaths()
}

public struct MacCapabilityShellToolPaths: Equatable, Sendable {
    public var id: URL
    public var which: URL
    public var env: URL

    public init(
        id: URL? = nil,
        which: URL? = nil,
        env: URL? = nil
    ) {
        self.id = id ?? SystemToolPathFactory.usrBin("id")
        self.which = which ?? SystemToolPathFactory.usrBin("which")
        self.env = env ?? SystemToolPathFactory.usrBin("env")
    }

    public static let macOSDefault = MacCapabilityShellToolPaths()
}

public struct MacCapabilitySecurityToolPaths: Equatable, Sendable {
    public var csrutil: URL
    public var fdesetup: URL
    public var profiles: URL

    public init(
        csrutil: URL? = nil,
        fdesetup: URL? = nil,
        profiles: URL? = nil
    ) {
        self.csrutil = csrutil ?? SystemToolPathFactory.usrBin("csrutil")
        self.fdesetup = fdesetup ?? SystemToolPathFactory.usrBin("fdesetup")
        self.profiles = profiles ?? SystemToolPathFactory.usrBin("profiles")
    }

    public static let macOSDefault = MacCapabilitySecurityToolPaths()
}

public struct MacCapabilityApplicationPaths: Equatable, Sendable {
    public var iCloudDocumentsPathComponents: [String]
    public var appStoreApplicationLocations: [URL]

    public init(
        iCloudDocumentsPathComponents: [String] = ["Library", "Mobile Documents"],
        appStoreApplicationLocations: [URL]? = nil
    ) {
        self.iCloudDocumentsPathComponents = iCloudDocumentsPathComponents
        self.appStoreApplicationLocations = appStoreApplicationLocations ?? [
            SystemToolPathFactory.systemApplication("App Store.app"),
            SystemToolPathFactory.userApplication("App Store.app")
        ]
    }

    public func iCloudDocumentsURL(relativeTo homeDirectory: URL) -> URL {
        iCloudDocumentsPathComponents.reduce(homeDirectory) { url, component in
            url.appendingPathComponent(component)
        }
    }

    public static let macOSDefault = MacCapabilityApplicationPaths()
}

public struct MacCapabilityHomebrewPrefixes: Equatable, Sendable {
    public var appleSilicon: URL
    public var intel: URL

    public init(
        appleSilicon: URL? = nil,
        intel: URL? = nil
    ) {
        self.appleSilicon = appleSilicon ?? SystemToolPathFactory.absoluteURL(["opt", "homebrew"])
        self.intel = intel ?? SystemToolPathFactory.absoluteURL(["usr", "local"])
    }

    public static let macOSDefault = MacCapabilityHomebrewPrefixes()

    fileprivate var executableCandidates: [URL] {
        [appleSilicon, intel].map { $0.appendingPathComponent("bin").appendingPathComponent("brew") }
    }
}

private struct ResolvedHomebrewCommand {
    var executable: URL
    var argumentPrefix: [String]
    var prefixResult: CommandResult

    func run(_ arguments: [String], runner: CommandRunner) async -> CommandResult {
        do {
            return try await runner.run(
                executable: executable,
                arguments: argumentPrefix + arguments,
                environment: nil
            )
        } catch {
            return CommandResult(
                executable: executable.path,
                arguments: argumentPrefix + arguments,
                exitCode: 1,
                standardError: String(describing: error)
            )
        }
    }
}

private extension CommandResult {
    var combinedOutput: String {
        [standardOutput, standardError].joined(separator: "\n")
    }
}
