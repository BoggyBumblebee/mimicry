import Foundation

public struct MimicrySnapshotBuildResult: Sendable {
    public var package: MimicryPackage
    public var capabilities: MacCapabilities

    public init(package: MimicryPackage, capabilities: MacCapabilities) {
        self.package = package
        self.capabilities = capabilities
    }
}

public struct MimicrySnapshotBuilder {
    public typealias CapabilitiesProvider = @Sendable () async -> MacCapabilities

    private let runner: CommandRunner
    private let packageStore: MimicryPackageStore
    private let providers: [any ConfigurationProvider]
    private let capabilitiesProvider: CapabilitiesProvider
    private let mimicryVersion: String

    public init(
        runner: CommandRunner = ProcessCommandRunner(),
        packageStore: MimicryPackageStore = MimicryPackageStore(),
        providers: [any ConfigurationProvider] = [
            EnvironmentSnapshotProvider(),
            HomebrewSnapshotProvider(),
            AppStoreSnapshotProvider(),
            FinderSnapshotProvider(),
            TerminalSnapshotProvider(),
            ICloudSnapshotProvider(),
            SafariBookmarksProvider()
        ],
        mimicryVersion: String = "0.1.0",
        capabilitiesProvider: CapabilitiesProvider? = nil
    ) {
        self.runner = runner
        self.packageStore = packageStore
        self.providers = providers
        self.mimicryVersion = mimicryVersion
        self.capabilitiesProvider = capabilitiesProvider ?? {
            await MacCapabilitiesDetector(runner: runner).detect()
        }
    }

    public func writeSnapshot(to packageURL: URL) async throws -> MimicrySnapshotBuildResult {
        let (snapshot, capabilities) = try await buildSnapshot()
        let package = try packageStore.write(snapshot: snapshot, to: packageURL)
        return MimicrySnapshotBuildResult(package: package, capabilities: capabilities)
    }

    public func buildSnapshot() async throws -> (snapshot: MimicrySnapshot, capabilities: MacCapabilities) {
        let capabilities = await capabilitiesProvider()
        let context = SnapshotContext(commandRunner: runner, capabilities: capabilities)
        var sections: [SnapshotSection] = []

        for provider in providers {
            sections.append(try await provider.snapshot(context: context))
        }

        let snapshot = MimicrySnapshot(
            mimicryVersion: mimicryVersion,
            source: SnapshotSource(capabilities: capabilities),
            sections: sections
        )
        return (snapshot, capabilities)
    }
}

public extension SnapshotSource {
    init(capabilities: MacCapabilities) {
        self.init(
            macOSVersion: capabilities.macOSVersion,
            architecture: capabilities.architecture.rawValue,
            hardwareModel: capabilities.hardwareModel,
            hostname: capabilities.hostname,
            username: capabilities.username
        )
    }
}
