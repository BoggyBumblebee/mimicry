import Foundation

public struct ProviderRegistry: Sendable {
    private var providers: [String: any ConfigurationProvider]

    public init(providers: [any ConfigurationProvider] = []) {
        self.providers = Dictionary(
            uniqueKeysWithValues: providers.map { ($0.identifier, $0) }
        )
    }

    public var allProviders: [any ConfigurationProvider] {
        providers.values.sorted { $0.identifier < $1.identifier }
    }

    public func provider(identifier: String) -> (any ConfigurationProvider)? {
        providers[identifier]
    }

    public mutating func register(_ provider: any ConfigurationProvider) {
        providers[provider.identifier] = provider
    }
}
