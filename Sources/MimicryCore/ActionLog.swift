import Foundation

public struct ActionLogEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    public var providerIdentifier: String
    public var operation: String
    public var status: OperationStatus
    public var reason: String?
    public var error: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        providerIdentifier: String,
        operation: String,
        status: OperationStatus,
        reason: String? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.providerIdentifier = providerIdentifier
        self.operation = operation
        self.status = status
        self.reason = reason
        self.error = error
    }
}
