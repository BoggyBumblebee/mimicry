import CryptoKit
import Foundation

public struct MimicryPackageManifest: Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var createdAt: Date
    public var snapshotPath: String
    public var encryptedDirectoryPath: String

    public init(
        formatVersion: Int = 1,
        createdAt: Date = Date(),
        snapshotPath: String = "snapshot.json",
        encryptedDirectoryPath: String = "encrypted"
    ) {
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.snapshotPath = snapshotPath
        self.encryptedDirectoryPath = encryptedDirectoryPath
    }
}

public struct MimicryPackageChecksums: Codable, Equatable, Sendable {
    public var algorithm: String
    public var files: [String: String]

    public init(
        algorithm: String = "sha256",
        files: [String: String]
    ) {
        self.algorithm = algorithm
        self.files = files
    }
}

public struct MimicryPackage: Sendable {
    public var url: URL
    public var manifest: MimicryPackageManifest
    public var snapshot: MimicrySnapshot

    public init(
        url: URL,
        manifest: MimicryPackageManifest,
        snapshot: MimicrySnapshot
    ) {
        self.url = url
        self.manifest = manifest
        self.snapshot = snapshot
    }
}

public enum MimicryPackageError: Error, Equatable, Sendable {
    case invalidExtension(String)
    case missingSnapshot
    case checksumMismatch(path: String)
}

public struct MimicryPackageStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func write(
        snapshot: MimicrySnapshot,
        to packageURL: URL,
        manifest: MimicryPackageManifest = MimicryPackageManifest()
    ) throws -> MimicryPackage {
        try validatePackageExtension(packageURL)

        try fileManager.createDirectory(
            at: packageURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: packageURL.appendingPathComponent("logs", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: packageURL.appendingPathComponent("browser", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: packageURL.appendingPathComponent("applications", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: packageURL.appendingPathComponent(manifest.encryptedDirectoryPath, isDirectory: true),
            withIntermediateDirectories: true
        )

        try encoder.encode(manifest).write(
            to: packageURL.appendingPathComponent("manifest.json"),
            options: .atomic
        )
        try encoder.encode(snapshot).write(
            to: packageURL.appendingPathComponent(manifest.snapshotPath),
            options: .atomic
        )

        let readme = """
        # Mimicry Snapshot

        This package contains a Mimicry snapshot. Open it with Mimicry or inspect the JSON files directly.

        Normal snapshot sections must not contain passwords, private keys, tokens, cookies, or authentication state.
        """
        try Data(readme.utf8).write(
            to: packageURL.appendingPathComponent("README.md"),
            options: .atomic
        )

        let checksums = try checksums(for: packageURL, paths: [
            "manifest.json",
            manifest.snapshotPath,
            "README.md"
        ])
        try encoder.encode(checksums).write(
            to: packageURL.appendingPathComponent("checksums.json"),
            options: .atomic
        )

        return MimicryPackage(
            url: packageURL,
            manifest: manifest,
            snapshot: snapshot
        )
    }

    public func read(from packageURL: URL) throws -> MimicryPackage {
        try validatePackageExtension(packageURL)

        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        let manifest = try decoder.decode(
            MimicryPackageManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let snapshotURL = packageURL.appendingPathComponent(manifest.snapshotPath)
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            throw MimicryPackageError.missingSnapshot
        }

        try validateChecksums(in: packageURL)

        let snapshot = try decoder.decode(
            MimicrySnapshot.self,
            from: Data(contentsOf: snapshotURL)
        )

        return MimicryPackage(
            url: packageURL,
            manifest: manifest,
            snapshot: snapshot
        )
    }

    private func validatePackageExtension(_ packageURL: URL) throws {
        guard packageURL.pathExtension == "mimicry" else {
            throw MimicryPackageError.invalidExtension(packageURL.pathExtension)
        }
    }

    private func validateChecksums(in packageURL: URL) throws {
        let checksumURL = packageURL.appendingPathComponent("checksums.json")
        guard fileManager.fileExists(atPath: checksumURL.path) else {
            return
        }

        let expected = try decoder.decode(
            MimicryPackageChecksums.self,
            from: Data(contentsOf: checksumURL)
        )
        let actual = try checksums(for: packageURL, paths: Array(expected.files.keys))

        for (path, checksum) in expected.files where actual.files[path] != checksum {
            throw MimicryPackageError.checksumMismatch(path: path)
        }
    }

    private func checksums(
        for packageURL: URL,
        paths: [String]
    ) throws -> MimicryPackageChecksums {
        var files: [String: String] = [:]

        for path in paths.sorted() {
            let fileURL = packageURL.appendingPathComponent(path)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                continue
            }

            let digest = SHA256.hash(data: try Data(contentsOf: fileURL))
            files[path] = digest.map { String(format: "%02x", $0) }.joined()
        }

        return MimicryPackageChecksums(files: files)
    }
}
