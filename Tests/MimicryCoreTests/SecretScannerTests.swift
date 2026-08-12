import MimicryCore
import XCTest

final class SecretScannerTests: XCTestCase {
    func testScannerFindsLikelyShellSecretsWithoutCapturingValues() {
        let exportedName = [["OPEN", "AI"].joined(), "API", "KEY"].joined(separator: "_")
        let sampleValue = ["example", "redacted", "value"].joined(separator: "-")
        let awsKey = ["AK", "IA"].joined() + "1234567890ABCDEF"
        let awsName = ["AWS", "ACCESS", "KEY", "ID"].joined(separator: "_")
        let privateKeyHeader = "-----BEGIN OPENSSH " + "PRIVATE" + " KEY-----"
        let result = SecretScanner().scan(
            """
            export \(exportedName)="\(sampleValue)"
            \(awsName)=\(awsKey)
            \(privateKeyHeader)
            """
        )

        XCTAssertEqual(result.findings.count, 4)
        XCTAssertEqual(result.ruleIDs, [
            "aws-access-key",
            "exported-secret",
            "private-key",
            "secret-assignment"
        ])
        XCTAssertEqual(result.findings.map(\.lineNumber), [1, 1, 2, 3])
    }

    func testScannerIgnoresOrdinaryShellConfiguration() {
        let result = SecretScanner().scan(
            """
            export PATH="$HOME/bin:$PATH"
            alias ll="ls -la"
            setopt autocd
            """
        )

        XCTAssertTrue(result.isClean)
        XCTAssertEqual(result.ruleIDs, [])
    }
}
