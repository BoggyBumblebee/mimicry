import Foundation

struct BrowserBookmarkURLSanitizer {
    func sanitize(_ rawValue: String?) -> SanitizedBookmarkURL {
        guard let rawValue, let trimmed = rawValue.trimmedNilIfEmpty else {
            return SanitizedBookmarkURL(value: "absent", redaction: "none")
        }

        guard var components = URLComponents(string: trimmed) else {
            return SanitizedBookmarkURL(value: "invalid", redaction: "invalid-url")
        }

        let hadQuery = components.query != nil
        let hadFragment = components.fragment != nil
        components.query = nil
        components.fragment = nil

        let redactions = [
            hadQuery ? "query" : nil,
            hadFragment ? "fragment" : nil
        ].compactMap { $0 }

        return SanitizedBookmarkURL(
            value: components.string ?? trimmed,
            redaction: redactions.isEmpty ? "none" : redactions.joined(separator: ",")
        )
    }
}

struct SanitizedBookmarkURL: Equatable, Sendable {
    var value: String
    var redaction: String

    var didRedact: Bool {
        redaction != "none" && redaction != "invalid-url"
    }
}
