import Darwin
import Foundation

public protocol CommandRunner: Sendable {
    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]?
    ) async throws -> CommandResult
}

public struct ProcessCommandRunner: CommandRunner {
    private let timeout: TimeInterval?

    public init(timeout: TimeInterval? = 30) {
        self.timeout = timeout
    }

    public func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> CommandResult {
        try await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let environment {
                process.environment = environment
            }

            let standardOutput = Pipe()
            let standardError = Pipe()
            process.standardOutput = standardOutput
            process.standardError = standardError

            let timeoutState = CommandTimeoutState()
            try process.run()
            let timer = timeout.map { timeout in
                let timer = DispatchSource.makeTimerSource()
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler {
                    timeoutState.markTimedOut()
                    if process.isRunning {
                        process.terminate()
                        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                            if process.isRunning {
                                kill(process.processIdentifier, SIGKILL)
                            }
                        }
                    }
                }
                timer.resume()
                return timer
            }
            process.waitUntilExit()
            timer?.cancel()

            let didTimeOut = timeoutState.didTimeOut

            return CommandResult(
                executable: executable.path,
                arguments: arguments,
                exitCode: didTimeOut ? 124 : process.terminationStatus,
                standardOutput: String(data: standardOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                standardError: commandErrorOutput(
                    String(data: standardError.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                    timedOutAfter: didTimeOut ? timeout : nil
                )
            )
        }.value
    }
}

private final class CommandTimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var timedOut = false

    var didTimeOut: Bool {
        lock.withLock {
            timedOut
        }
    }

    func markTimedOut() {
        lock.withLock {
            timedOut = true
        }
    }
}

private func commandErrorOutput(_ standardError: String, timedOutAfter timeout: TimeInterval?) -> String {
    guard let timeout else {
        return standardError
    }

    let timeoutMessage = "Command timed out after \(String(format: "%.1f", timeout)) seconds."
    guard standardError.trimmedNilIfEmpty != nil else {
        return timeoutMessage
    }
    return standardError.hasSuffix("\n")
        ? standardError + timeoutMessage
        : standardError + "\n" + timeoutMessage
}

public struct CommandResult: Codable, Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public init(
        executable: String,
        arguments: [String],
        exitCode: Int32,
        standardOutput: String = "",
        standardError: String = ""
    ) {
        self.executable = executable
        self.arguments = arguments
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public actor FakeCommandRunner: CommandRunner {
    public private(set) var invocations: [CommandInvocation] = []
    private var results: [CommandResult]

    public init(results: [CommandResult] = []) {
        self.results = results
    }

    public func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> CommandResult {
        invocations.append(
            CommandInvocation(
                executable: executable.path,
                arguments: arguments,
                environment: environment
            )
        )

        if results.isEmpty {
            return CommandResult(
                executable: executable.path,
                arguments: arguments,
                exitCode: 0
            )
        }

        var result = results.removeFirst()
        result.executable = executable.path
        result.arguments = arguments
        return result
    }
}

public struct CommandInvocation: Codable, Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]?

    public init(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }
}
