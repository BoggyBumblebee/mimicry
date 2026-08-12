import Foundation

public struct MacCapabilities: Codable, Equatable, Sendable {
    public var macOSVersion: String
    public var architecture: MacArchitecture
    public var hardwareModel: String
    public var hostname: String
    public var username: String
    public var hasAdministratorPrivileges: Bool
    public var fileVaultState: CapabilityState
    public var sipState: CapabilityState
    public var hasCommandLineTools: Bool
    public var xcodeVersion: String?
    public var homebrew: HomebrewCapability
    public var hasMAS: Bool
    public var iCloudState: CapabilityState
    public var appStoreState: CapabilityState
    public var managementState: CapabilityState

    public init(
        macOSVersion: String,
        architecture: MacArchitecture,
        hardwareModel: String,
        hostname: String,
        username: String,
        hasAdministratorPrivileges: Bool = false,
        fileVaultState: CapabilityState = .unknown,
        sipState: CapabilityState = .unknown,
        hasCommandLineTools: Bool = false,
        xcodeVersion: String? = nil,
        homebrew: HomebrewCapability = HomebrewCapability(),
        hasMAS: Bool = false,
        iCloudState: CapabilityState = .unknown,
        appStoreState: CapabilityState = .unknown,
        managementState: CapabilityState = .unknown
    ) {
        self.macOSVersion = macOSVersion
        self.architecture = architecture
        self.hardwareModel = hardwareModel
        self.hostname = hostname
        self.username = username
        self.hasAdministratorPrivileges = hasAdministratorPrivileges
        self.fileVaultState = fileVaultState
        self.sipState = sipState
        self.hasCommandLineTools = hasCommandLineTools
        self.xcodeVersion = xcodeVersion
        self.homebrew = homebrew
        self.hasMAS = hasMAS
        self.iCloudState = iCloudState
        self.appStoreState = appStoreState
        self.managementState = managementState
    }
}

public enum MacArchitecture: String, Codable, Equatable, Sendable {
    case arm64
    case x86_64
    case unknown

    public var isAppleSilicon: Bool {
        self == .arm64
    }
}

public enum CapabilityState: String, Codable, Equatable, Sendable {
    case available
    case unavailable
    case enabled
    case disabled
    case managed
    case requiresUserAction
    case unsupported
    case unknown
}

public struct HomebrewCapability: Codable, Equatable, Sendable {
    public var isInstalled: Bool
    public var prefix: String?
    public var architecture: MacArchitecture

    public init(
        isInstalled: Bool = false,
        prefix: String? = nil,
        architecture: MacArchitecture = .unknown
    ) {
        self.isInstalled = isInstalled
        self.prefix = prefix
        self.architecture = architecture
    }
}
