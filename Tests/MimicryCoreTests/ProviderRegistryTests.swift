import MimicryCore
import XCTest

final class ProviderRegistryTests: XCTestCase {
    func testRegistryReturnsProvidersInStableIdentifierOrder() {
        let alpha = StubProvider(identifier: "alpha")
        let beta = StubProvider(identifier: "beta")
        let zeta = StubProvider(identifier: "zeta")

        let registry = ProviderRegistry(providers: [zeta, alpha, beta])

        XCTAssertEqual(
            registry.allProviders.map(\.identifier),
            ["alpha", "beta", "zeta"]
        )
        XCTAssertEqual(registry.provider(identifier: "beta")?.displayName, "beta")
    }

    func testRegistryCanRegisterProvider() {
        var registry = ProviderRegistry()

        registry.register(StubProvider(identifier: "environment"))

        XCTAssertEqual(registry.provider(identifier: "environment")?.identifier, "environment")
    }
}

private struct StubProvider: ConfigurationProvider {
    var identifier: String
    var displayName: String { identifier }
    var capabilities: ProviderCapabilities { ProviderCapabilities() }

    func detect(context: DetectionContext) async throws -> DetectionResult {
        DetectionResult(providerIdentifier: identifier, status: .success, message: "detected")
    }

    func snapshot(context: SnapshotContext) async throws -> SnapshotSection {
        SnapshotSection(identifier: identifier, displayName: displayName)
    }

    func validate(section: SnapshotSection, context: ValidationContext) async throws -> ValidationResult {
        ValidationResult(status: .success)
    }

    func planApply(section: SnapshotSection, context: ApplyContext) async throws -> [PlannedAction] {
        []
    }

    func apply(action: PlannedAction, context: ApplyContext) async throws -> ApplyResult {
        ApplyResult(actionID: action.id, status: .skipped, message: "stub")
    }
}
