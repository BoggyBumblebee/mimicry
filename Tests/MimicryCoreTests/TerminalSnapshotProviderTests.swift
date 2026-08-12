import MimicryCore
import XCTest

final class TerminalSnapshotProviderTests: XCTestCase {
    func testSnapshotCapturesShellMetadataAndSafeConfigMetadata() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        try write(
            """
            export PATH="$HOME/bin:$PATH"
            alias ll="ls -la"
            """,
            to: ".zshrc",
            in: homeDirectory
        )

        let provider = TerminalSnapshotProvider(
            homeDirectory: homeDirectory,
            environment: [
                "SHELL": "/bin/zsh",
                "TERM": "xterm-256color",
                "TERM_PROGRAM": "Apple_Terminal",
                "UNRELATED_ENV": "not-captured"
            ],
            configFiles: [
                TerminalConfigurationFileSpec(relativePath: ".zshrc", displayName: "zshrc")
            ]
        )

        let section = try await provider.snapshot(context: SnapshotContext(commandRunner: FakeCommandRunner()))

        XCTAssertEqual(section.identifier, "terminal")
        XCTAssertEqual(section.warnings, [])
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "terminal.shell.path",
                value: .string("/bin/zsh"),
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "terminal.shell.name",
                value: .string("zsh"),
                applicability: .userSpecific
            )
        ))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "terminal.term",
                value: .string("xterm-256color"),
                applicability: .userSpecific
            )
        ))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "terminal.term-program",
                value: .string("Apple_Terminal"),
                applicability: .userSpecific
            )
        ))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "terminal.config.zshrc",
                value: .object([
                    "path": ".zshrc",
                    "displayName": "zshrc",
                    "status": "metadata-captured",
                    "lineCount": "2",
                    "secretFindingCount": "0"
                ]),
                applicability: .userSpecific
            )
        ))
    }

    func testSnapshotRedactsConfigFilesWithSecretLikeValues() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        let exportedName = [["OPEN", "AI"].joined(), "API", "KEY"].joined(separator: "_")
        let sampleValue = ["example", "redacted", "value"].joined(separator: "-")
        try write(
            """
            export \(exportedName)="\(sampleValue)"
            alias ll="ls -la"
            """,
            to: ".zprofile",
            in: homeDirectory
        )

        let provider = TerminalSnapshotProvider(
            homeDirectory: homeDirectory,
            environment: [:],
            configFiles: [
                TerminalConfigurationFileSpec(relativePath: ".zprofile", displayName: "zprofile")
            ]
        )

        let section = try await provider.snapshot(context: SnapshotContext(commandRunner: FakeCommandRunner()))

        XCTAssertEqual(section.warnings.map(\.code), ["terminal.config-redacted.zprofile"])
        let item = try XCTUnwrap(section.items.first { $0.key == "terminal.config.zprofile" })
        XCTAssertEqual(item.classification, .potentiallySensitive)
        XCTAssertEqual(item.applicability, .userSpecific)
        XCTAssertEqual(
            item.value,
            .object([
                "path": ".zprofile",
                "displayName": "zprofile",
                "status": "redacted",
                "lineCount": "2",
                "secretFindingCount": "2",
                "secretRules": "exported-secret,secret-assignment"
            ])
        )
        XCTAssertFalse(String(describing: item.value).contains(sampleValue))
    }

    func testSnapshotMarksMissingConfigFilesAbsent() async throws {
        let provider = TerminalSnapshotProvider(
            homeDirectory: try makeTemporaryDirectory(),
            environment: [:],
            configFiles: [
                TerminalConfigurationFileSpec(relativePath: ".bashrc", displayName: "bashrc")
            ]
        )

        let section = try await provider.snapshot(context: SnapshotContext(commandRunner: FakeCommandRunner()))

        XCTAssertEqual(section.warnings, [])
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "terminal.config.bashrc",
                value: .object([
                    "path": ".bashrc",
                    "displayName": "bashrc",
                    "status": "absent",
                    "lineCount": "0",
                    "secretFindingCount": "0"
                ]),
                applicability: .userSpecific
            )
        ))
    }

    func testDetectAndLifecycleMethodsDeferApplyToLaterPhase() async throws {
        let provider = TerminalSnapshotProvider()
        let detection = try await provider.detect(context: DetectionContext(commandRunner: FakeCommandRunner()))
        let valid = try await provider.validate(
            section: SnapshotSection(identifier: "terminal", displayName: "Terminal"),
            context: ValidationContext()
        )
        let invalid = try await provider.validate(
            section: SnapshotSection(identifier: "other", displayName: "Other"),
            context: ValidationContext()
        )
        let actions = try await provider.planApply(
            section: SnapshotSection(identifier: "terminal", displayName: "Terminal"),
            context: ApplyContext(commandRunner: FakeCommandRunner())
        )
        let result = try await provider.apply(
            action: actions[0],
            context: ApplyContext(commandRunner: FakeCommandRunner())
        )

        XCTAssertEqual(detection.status, .success)
        XCTAssertEqual(valid.status, .success)
        XCTAssertEqual(invalid.status, .warning)
        XCTAssertEqual(actions.map(\.kind), [.requiresUserAction])
        XCTAssertEqual(result.status, .skipped)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func write(_ content: String, to relativePath: String, in homeDirectory: URL) throws {
        let url = homeDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
