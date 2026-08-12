import MimicryCore
import XCTest

final class CommandRunnerTests: XCTestCase {
    func testProcessCommandRunnerExecutesCommandAndCapturesOutput() async throws {
        let runner = ProcessCommandRunner()

        let result = try await runner.run(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["mimicry"],
            environment: nil
        )

        XCTAssertEqual(result.executable, "/bin/echo")
        XCTAssertEqual(result.arguments, ["mimicry"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput, "mimicry\n")
        XCTAssertEqual(result.standardError, "")
    }

    func testProcessCommandRunnerAppliesExplicitEnvironment() async throws {
        let runner = ProcessCommandRunner()

        let result = try await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [],
            environment: ["MIMICRY_TEST_ENV": "available"]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.standardOutput.contains("MIMICRY_TEST_ENV=available"))
    }

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

    func testFakeCommandRunnerReturnsDefaultSuccessWhenNoResultIsSeeded() async throws {
        let runner = FakeCommandRunner()

        let result = try await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/example"),
            arguments: [],
            environment: nil
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.executable, "/usr/bin/example")
    }
}
