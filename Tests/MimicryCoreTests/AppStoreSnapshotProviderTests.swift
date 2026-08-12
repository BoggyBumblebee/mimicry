import MimicryCore
import XCTest

final class AppStoreSnapshotProviderTests: XCTestCase {
    func testSnapshotCapturesMASApplications() async throws {
        let runner = FakeCommandRunner(results: [
            CommandResult(
                executable: "",
                arguments: [],
                exitCode: 0,
                standardOutput: """
                497799835 Xcode (16.4)
                1444383602 GoodNotes 6 (6.6.0)
                123456789 App With Parentheses (Mac) (1.2.3)
                """
            )
        ])

        let section = try await AppStoreSnapshotProvider().snapshot(
            context: SnapshotContext(commandRunner: runner)
        )

        XCTAssertEqual(section.identifier, "app-store")
        XCTAssertEqual(section.warnings, [])
        XCTAssertTrue(section.items.contains(SnapshotItem(key: "app-store.mas-available", value: .bool(true))))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "app-store.app.497799835",
                value: .object(["identifier": "497799835", "name": "Xcode", "version": "16.4"]),
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ))
        XCTAssertTrue(section.items.contains(
            SnapshotItem(
                key: "app-store.app.123456789",
                value: .object(["identifier": "123456789", "name": "App With Parentheses (Mac)", "version": "1.2.3"]),
                classification: .userMustReview,
                applicability: .userSpecific
            )
        ))

        let invocations = await runner.invocations
        XCTAssertEqual(invocations.map(\.arguments), [["mas", "list"]])
    }

    func testSnapshotWarnsWhenMASIsUnavailable() async throws {
        let runner = FakeCommandRunner(results: [
            CommandResult(executable: "", arguments: [], exitCode: 127, standardError: "mas not found")
        ])

        let section = try await AppStoreSnapshotProvider().snapshot(
            context: SnapshotContext(commandRunner: runner)
        )

        XCTAssertEqual(section.items, [
            SnapshotItem(key: "app-store.mas-available", value: .bool(false))
        ])
        XCTAssertEqual(section.warnings.map(\.code), ["app-store.mas-unavailable"])
    }
}
