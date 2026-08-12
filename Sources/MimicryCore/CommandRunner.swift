import Foundation

public protocol CommandRunner: Sendable {
    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]?
    ) async throws -> CommandResult
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
