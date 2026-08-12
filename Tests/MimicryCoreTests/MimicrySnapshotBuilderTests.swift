import MimicryCore
import XCTest

final class MimicrySnapshotBuilderTests: XCTestCase {
    func testBuilderWritesEnvironmentAndProviderSectionsToPackage() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let packageURL = temporaryDirectory.appendingPathComponent("phase-3c.mimicry")
        let runner = FakeCommandRunner(results: [
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "/opt/homebrew\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "Homebrew 5.0.0\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "homebrew/core\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: "swiftlint 0.59.0\n"),
            CommandResult(executable: "", arguments: [], exitCode: 0, standardOutput: ""),
            CommandResult(executable: "", arguments: [], exitCode: 127, standardError: "mas not found")
        ])
        let builder = MimicrySnapshotBuilder(
            runner: runner,
            providers: [
                EnvironmentSnapshotProvider(),
                HomebrewSnapshotProvider(),
                AppStoreSnapshotProvider(),
                FinderSnapshotProvider(preferences: []),
                TerminalSnapshotProvider(
                    homeDirectory: temporaryDirectory,
                    environment: ["SHELL": "/bin/zsh"],
                    configFiles: []
                ),
                ICloudSnapshotProvider(
                    homeDirectory: temporaryDirectory,
                    fileExists: { _ in false }
                ),
                SafariBookmarksProvider(
                    bookmarksURL: temporaryDirectory.appendingPathComponent("Bookmarks.plist"),
                    fileExists: { _ in false }
                ),
                ChromeBookmarksProvider(
                    chromeRootURL: temporaryDirectory.appendingPathComponent("Chrome", isDirectory: true),
                    fileExists: { _ in false }
                ),
                FirefoxBookmarksProvider(
                    firefoxRootURL: temporaryDirectory.appendingPathComponent("Firefox", isDirectory: true),
                    fileExists: { _ in false }
                )
            ],
            capabilitiesProvider: {
                MacCapabilities.phaseTwoBFixture()
            }
        )

        let result = try await builder.writeSnapshot(to: packageURL)
        let package = try MimicryPackageStore().read(from: packageURL)

        XCTAssertEqual(result.package.url.path, packageURL.standardizedFileURL.path)
        XCTAssertEqual(package.snapshot.sections.map(\.identifier), ["environment", "homebrew", "app-store", "finder", "terminal", "icloud", "safari", "chrome", "firefox"])
        XCTAssertEqual(package.snapshot.source.hostname, "reference-mac.local")
        XCTAssertTrue(package.snapshot.sections.flatMap(\.warnings).contains(SnapshotWarning(code: "app-store.mas-unavailable", message: "`mas` was not available; App Store applications were not captured.")))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}

private extension MacCapabilities {
    static func phaseTwoBFixture() -> MacCapabilities {
        MacCapabilities(
            environment: MacEnvironment(
                macOSVersion: "Version 26.0",
                architecture: .arm64,
                hardwareModel: "MacBookPro18,3",
                hostname: "reference-mac.local",
                username: "cmb"
            ),
            security: MacSecurityCapabilities(
                hasAdministratorPrivileges: true,
                fileVaultState: .enabled,
                sipState: .enabled
            ),
            tools: MacToolCapabilities(
                hasCommandLineTools: true,
                xcodeVersion: "Xcode 26.0",
                homebrew: HomebrewCapability(
                    isInstalled: true,
                    prefix: "/opt/homebrew",
                    version: "Homebrew 5.0.0",
                    architecture: .arm64
                ),
                hasMAS: false
            ),
            services: MacServiceCapabilities(
                iCloudState: .available,
                appStoreState: .available,
                managementState: .unknown
            )
        )
    }
}
