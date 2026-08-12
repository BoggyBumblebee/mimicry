import Foundation

public struct SecretScanner: Sendable {
    public var rules: [SecretScanRule]

    public init(rules: [SecretScanRule] = SecretScanRule.defaultRules) {
        self.rules = rules
    }

    public func scan(_ content: String) -> SecretScanResult {
        var findings: [SecretScanFinding] = []
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        for (offset, line) in lines.enumerated() {
            let lineValue = String(line)

            for rule in rules where rule.matches(lineValue) {
                findings.append(
                    SecretScanFinding(
                        ruleID: rule.id,
                        lineNumber: offset + 1
                    )
                )
            }
        }

        return SecretScanResult(findings: findings)
    }
}

public struct SecretScanRule: Equatable, Sendable {
    public var id: String
    public var pattern: String

    public init(id: String, pattern: String) {
        self.id = id
        self.pattern = pattern
    }

    public static let defaultRules = [
        SecretScanRule(
            id: "private-key",
            pattern: "-----BEGIN [A-Z ]*PRIVATE KEY-----"
        ),
        SecretScanRule(
            id: "secret-assignment",
            pattern: #"(?i)\b(api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|github[_-]?token|openai[_-]?api[_-]?key|password|passwd|secret)\b\s*=\s*['"]?[^'"\s#]+"#
        ),
        SecretScanRule(
            id: "exported-secret",
            pattern: #"(?i)^\s*export\s+[A-Z0-9_]*(API[_-]?KEY|ACCESS[_-]?TOKEN|AUTH[_-]?TOKEN|CLIENT[_-]?SECRET|GITHUB[_-]?TOKEN|OPENAI[_-]?API[_-]?KEY|PASSWORD|PASSWD|SECRET)[A-Z0-9_]*\s*="#
        ),
        SecretScanRule(
            id: "aws-access-key",
            pattern: #"\bAKIA[0-9A-Z]{16}\b"#
        ),
        SecretScanRule(
            id: "bearer-token",
            pattern: #"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{20,}"#
        )
    ]

    func matches(_ line: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return false
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return expression.firstMatch(in: line, range: range) != nil
    }
}

public struct SecretScanResult: Equatable, Sendable {
    public var findings: [SecretScanFinding]

    public init(findings: [SecretScanFinding]) {
        self.findings = findings
    }

    public var isClean: Bool {
        findings.isEmpty
    }

    public var ruleIDs: [String] {
        Array(Set(findings.map(\.ruleID))).sorted()
    }
}

public struct SecretScanFinding: Equatable, Sendable {
    public var ruleID: String
    public var lineNumber: Int

    public init(ruleID: String, lineNumber: Int) {
        self.ruleID = ruleID
        self.lineNumber = lineNumber
    }
}
