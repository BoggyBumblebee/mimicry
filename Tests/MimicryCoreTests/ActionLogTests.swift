import MimicryCore
import XCTest

final class ActionLogTests: XCTestCase {
    func testActionLogEntryKeepsOperationContext() {
        let id = UUID(uuidString: "24D49F68-7A0D-4C10-81EE-2F8A5362E7D0")!
        let timestamp = Date(timeIntervalSince1970: 1_786_492_800)

        let entry = ActionLogEntry(
            id: id,
            timestamp: timestamp,
            providerIdentifier: "homebrew",
            operation: "detect",
            status: .success,
            reason: "read-only probe",
            error: nil
        )

        XCTAssertEqual(entry.id, id)
        XCTAssertEqual(entry.timestamp, timestamp)
        XCTAssertEqual(entry.providerIdentifier, "homebrew")
        XCTAssertEqual(entry.operation, "detect")
        XCTAssertEqual(entry.status, .success)
        XCTAssertEqual(entry.reason, "read-only probe")
        XCTAssertNil(entry.error)
    }
}
