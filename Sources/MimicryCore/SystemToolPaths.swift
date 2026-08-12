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

    public init(env: URL? = nil) {
        self.env = env ?? SystemToolPathFactory.usrBin("env")
    }

    public static let macOSDefault = SnapshotProviderToolPaths()
}

extension String {
    var trimmedNilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
