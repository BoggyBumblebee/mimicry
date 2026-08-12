import MimicryCore
import XCTest

final class CommandRunnerTests: XCTestCase {
    func testFakeCommandRunnerRecordsInvocationAndReturnsSeededResult() async throws {
        let runner = FakeCommandRunner(results: [
            CommandResult(
                executable: "",
                arguments: [],
                exitCode: 7,
                standardOutput: "hello",
                standardError: "warning"
            )
        ])

        let result = try await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/example"),
            arguments: ["--flag"],
            environment: ["MIMICRY": "1"]
        )
        let invocations = await runner.invocations

        XCTAssertEqual(result.executable, "/usr/bin/example")
        XCTAssertEqual(result.arguments, ["--flag"])
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertEqual(result.standardOutput, "hello")
        XCTAssertEqual(result.standardError, "warning")
        XCTAssertEqual(invocations, [
            CommandInvocation(
                executable: "/usr/bin/example",
                arguments: ["--flag"],
                environment: ["MIMICRY": "1"]
            )
        ])
    }
}
