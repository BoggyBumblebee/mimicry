import Foundation

struct DisplayPathFormatter {
    static func userFacingPath(
        for url: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        let path = url.standardizedFileURL.path
        let homePath = homeDirectory.standardizedFileURL.path

        if path == homePath {
            return "~"
        }

        let homePrefix = homePath + "/"
        if path.hasPrefix(homePrefix) {
            return "~" + "/" + path.dropFirst(homePrefix.count)
        }

        return path
    }
}
