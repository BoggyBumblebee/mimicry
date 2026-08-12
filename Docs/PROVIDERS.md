# Providers

Mimicry should support configuration through explicit providers. Providers detect, snapshot, validate, plan, and apply only the data they understand.

```swift
protocol ConfigurationProvider {
    var identifier: String { get }
    var displayName: String { get }
    var capabilities: ProviderCapabilities { get }

    func detect(context: DetectionContext) async throws -> DetectionResult
    func snapshot(context: SnapshotContext) async throws -> SnapshotSection
    func validate(section: SnapshotSection, context: ValidationContext) async throws -> ValidationResult
    func planApply(section: SnapshotSection, context: ApplyContext) async throws -> [PlannedAction]
    func apply(action: PlannedAction, context: ApplyContext) async throws -> ApplyResult
}
```

Providers are collected through `ProviderRegistry`, which provides stable identifier-based lookup and deterministic provider ordering. Snapshot builders can also receive an explicit provider list when command workflows need a fixed capture order.

## Classification

Each provider must classify data as:

- safe configuration
- potentially sensitive
- excluded
- user must review
- machine-specific
- hardware-specific
- managed
- unsupported

## MVP Providers

- Environment and capabilities: implemented for read-only snapshot metadata.
- Homebrew: implemented for read-only taps, formulae, casks, prefix, version, and architecture.
- Mac App Store through `mas`: implemented for read-only App Store application inventory when `mas` is available.
- Finder basics
- Terminal basics
- iCloud state detection
- Safari bookmarks/configuration
- Chrome bookmarks
- Firefox bookmarks

## Future Providers

- Dock
- VS Code
- iTerm2
- Git
- SSH public configuration
- Docker
- 1Password metadata only
- LaunchAgents
- Login items
- Fonts
- Printers
- VPN metadata
- External display and input-device settings

## Finder and Terminal Scope

Finder and Terminal should capture and apply as much as possible, but only when each setting is explicitly classified, validated, backed up where practical, and covered by tests.

Terminal providers must refuse or redact likely secrets by default.

## Phase 2 Snapshot Behavior

`mimicry snapshot` currently writes three non-mutating sections:

- `environment`
- `homebrew`
- `app-store`

Homebrew absence and `mas` absence are represented as warnings inside the relevant section. Neither provider installs, removes, upgrades, signs in, or changes system settings during snapshot.
