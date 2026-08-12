import MimicryCore
import XCTest

final class MimicryPackageStoreTests: XCTestCase {
    func testWriteAndReadPackageBundle() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let packageURL = temporaryDirectory.appendingPathComponent("primary-mac.mimicry")
        let snapshot = MimicrySnapshot.phaseOneFixture()

        let store = MimicryPackageStore()
        _ = try store.write(snapshot: snapshot, to: packageURL)
        let package = try store.read(from: packageURL)

        XCTAssertEqual(package.snapshot, snapshot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("manifest.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("checksums.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("encrypted").path))
    }

    func testRejectsUnexpectedPackageExtension() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let packageURL = temporaryDirectory.appendingPathComponent("primary-mac.json")

        XCTAssertThrowsError(try MimicryPackageStore().write(
            snapshot: .phaseOneFixture(),
            to: packageURL
        )) { error in
            XCTAssertEqual(error as? MimicryPackageError, .invalidExtension("json"))
        }
    }

    func testDetectsChecksumMismatch() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let packageURL = temporaryDirectory.appendingPathComponent("primary-mac.mimicry")

        let store = MimicryPackageStore()
        _ = try store.write(snapshot: .phaseOneFixture(), to: packageURL)
        try Data("tampered".utf8).write(
            to: packageURL.appendingPathComponent("snapshot.json"),
            options: .atomic
        )

        XCTAssertThrowsError(try store.read(from: packageURL)) { error in
            XCTAssertEqual(error as? MimicryPackageError, .checksumMismatch(path: "snapshot.json"))
        }
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
}
