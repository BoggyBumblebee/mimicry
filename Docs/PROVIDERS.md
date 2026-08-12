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
- Finder basics: implemented for stable preference inventory through `defaults read`, with the first confirmed safe apply path for boolean/string preferences through `defaults write`.
- Terminal basics: implemented for read-only shell metadata and shell config-file metadata with secret-like values redacted.
- iCloud state detection: implemented for read-only status metadata and required-user-action reporting without authentication capture.
- Safari bookmarks: implemented for read-only bookmark/folder metadata from `Bookmarks.plist`, with query strings and fragments removed from bookmark URLs.
- Safari configuration
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

## Current Snapshot Behavior

`mimicry snapshot` currently writes seven sections:

- `environment`
- `homebrew`
- `app-store`
- `finder`
- `terminal`
- `icloud`
- `safari`

Homebrew absence, `mas` absence, unreadable Finder preferences, unreadable Terminal files, Terminal files containing secret-like values, iCloud states requiring user action, and missing or unreadable Safari bookmarks are represented as warnings or absent/redacted/reviewable values inside the relevant section. Snapshot, inspect, validate, diff, and dry-run apply do not install, remove, upgrade, sign in, write preferences, edit shell files, read synced document contents, import bookmarks, or change system settings.

## Finder Preferences

The Finder provider captures a conservative read-only inventory of stable `com.apple.finder` preferences through `defaults read`, including visibility controls, view style, search scope, new-window target metadata, trash warning behavior, and desktop device visibility toggles.

Missing individual defaults are represented as absent values rather than failures. User-specific paths such as `NewWindowTargetPath` are marked for review.

`mimicry apply --confirm` can write only changed or missing Finder preferences that are classified as safe configuration and whose snapshot values are booleans or strings. It skips absent values, user-specific paths, sensitive values, managed values, and unsupported values, writes a backup before changing anything, and does not restart Finder.

## Terminal Metadata

The Terminal provider captures shell path/name and terminal environment metadata from a small allowlist: `SHELL`, `TERM`, and `TERM_PROGRAM`. It reviews common shell configuration file locations such as `.zshrc`, `.zprofile`, `.bashrc`, `.profile`, and fish config, but stores only metadata: path, display name, status, line count, secret finding count, and matching secret-rule IDs.

Shell configuration contents are not stored. Files with private-key markers, token/password assignments, AWS access keys, or bearer-token-like values are marked `potentiallySensitive` and redacted.

## iCloud Metadata

The iCloud provider captures local status metadata only: capability state, whether the expected iCloud Drive container path exists, and an explicit marker that authentication state is excluded. Missing local metadata is represented as `requiresUserAction`.

The provider does not read iCloud account databases, sync databases, document contents, tokens, sessions, cookies, Keychain items, or credentials.

## Safari Bookmarks

The Safari provider captures read-only bookmark and folder metadata from `~/Library/Safari/Bookmarks.plist` when it is present. Captured items include folder titles, folder paths, bookmark titles, bookmark folder paths, sanitized bookmark URLs, and counts for folders, bookmarks, and redacted URLs.

Safari bookmark data is marked `userMustReview` and `userSpecific`. Bookmark URL query strings and fragments are removed before capture because they can contain search terms, tracking data, tokens, or other private state. Missing bookmarks, unreadable plist data, and URL redaction counts are surfaced as warnings or source metadata.

The provider does not read cookies, history, passwords, sessions, autofill data, profile encryption keys, extensions, website storage, or Safari account state. Safari bookmark import/apply is not implemented yet.
