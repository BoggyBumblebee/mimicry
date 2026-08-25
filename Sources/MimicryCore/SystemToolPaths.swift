import Foundation

public enum SystemToolPathFactory {
    public static func usrBin(_ executableName: String) -> URL {
        absoluteURL(["usr", "bin", executableName])
    }

    public static func systemApplication(_ applicationName: String) -> URL {
        absoluteURL(["System", "Applications", applicationName])
    }

    public static func userApplication(_ applicationName: String) -> URL {
        absoluteURL(["Applications", applicationName])
    }

    public static func absoluteURL(_ components: [String]) -> URL {
        components.reduce(URL(fileURLWithPath: NSOpenStepRootDirectory(), isDirectory: true)) { url, component in
            url.appendingPathComponent(component)
        }
    }
}

public struct SnapshotProviderToolPaths: Equatable, Sendable {
    public var env: URL
    public var defaults: URL
    public var homebrewExecutableCandidates: [URL]
    public var masExecutableCandidates: [URL]

    public init(
        env: URL? = nil,
        defaults: URL? = nil,
        homebrewExecutableCandidates: [URL]? = nil,
        masExecutableCandidates: [URL]? = nil
    ) {
        self.env = env ?? SystemToolPathFactory.usrBin("env")
        self.defaults = defaults ?? SystemToolPathFactory.usrBin("defaults")
        self.homebrewExecutableCandidates = homebrewExecutableCandidates ?? HomebrewToolPaths.macOSDefault.executableCandidates
        self.masExecutableCandidates = masExecutableCandidates ?? HomebrewToolPaths.macOSDefault.masExecutableCandidates
    }

    public static let macOSDefault = SnapshotProviderToolPaths()
}

public struct HomebrewToolPaths: Equatable, Sendable {
    public var prefixes: [URL]

    public init(prefixes: [URL]? = nil) {
        self.prefixes = prefixes ?? [
            SystemToolPathFactory.absoluteURL(["opt", "homebrew"]),
            SystemToolPathFactory.absoluteURL(["usr", "local"])
        ]
    }

    public var executableCandidates: [URL] {
        prefixes.map { $0.appendingPathComponent("bin").appendingPathComponent("brew") }
    }

    public var masExecutableCandidates: [URL] {
        prefixes.map { $0.appendingPathComponent("bin").appendingPathComponent("mas") }
    }

    public static let macOSDefault = HomebrewToolPaths()
}

extension String {
    var trimmedNilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
