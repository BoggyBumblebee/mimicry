# Mimicry

Mimicry is a native macOS configuration declaration and reconciliation tool.

The core workflow is:

```text
Snapshot a known-good Mac.
Inspect exactly what was captured and excluded.
Apply that snapshot to another Mac safely, repeatably, and with clear explanations.
```

Mimicry is not a backup tool, disk clone, or credential migration utility. It should never try to copy an entire home directory, browser profile, Keychain, or `~/Library` tree. Its job is to describe the desired configuration of a Mac and make another Mac conform to that declaration as far as safely and technically possible.

The full build prompt is tracked in [PROMPT.md](PROMPT.md).

## Product Goal

Mimicry exists to replace the fragile parts of an Ansible-style Mac setup workflow with a modern macOS-native app. It should preserve the useful intent of a playbook: applications, Homebrew packages, App Store apps, shell setup, Finder preferences, browser bookmarks, and user-visible configuration. It should discard the unsafe parts: blindly copying files, storing credentials, bypassing macOS authentication, and assuming settings still work across macOS releases.

The target outcome is:

```bash
mimicry snapshot --output ~/Desktop/primary-mac.mimicry
mimicry doctor
mimicry apply ~/Desktop/primary-mac.mimicry --dry-run
mimicry apply ~/Desktop/primary-mac.mimicry
```

After apply, the destination Mac should be configured as closely as practical to the reference Mac while clearly reporting anything skipped, unsupported, incompatible, managed, excluded, or requiring user action.

## Existing Project Context

The implementation should learn from nearby BoggyBumblebee projects:

- [mac-os-playbook](https://github.com/BoggyBumblebee/mac-os-playbook): useful source of setup intent, including Homebrew packages, casks, App Store apps, dotfiles, Terminal configuration, Dock configuration, and post-provision hooks. Mimicry should not port this Ansible structure directly.
- [hodgepodge](https://github.com/BoggyBumblebee/hodgepodge): relevant Homebrew domain work, command execution, SwiftUI views, and XcodeGen project structure.
- [network-tools](https://github.com/BoggyBumblebee/network-tools): relevant SwiftUI service/model/view-model structure, validation patterns, logging utilities, unit tests, UI tests, and coverage-oriented schemes.
- [quickie](https://github.com/BoggyBumblebee/quickie): relevant lightweight macOS app structure, Swift 6 setup, app metadata, settings, launch-at-login patterns, and XcodeGen usage.
- [dotfiles](https://github.com/BoggyBumblebee/dotfiles): likely reference material for the Terminal and shell configuration providers, but never something to copy wholesale without secret scanning and explicit user review.

The broad pattern that fits Mimicry best is a native Swift project with a small, testable core and thin app/CLI fronts. Existing projects already show that XcodeGen plus SwiftUI works well in this workspace.

## Recommended Toolchain

Primary tools:

- Swift 6 and Swift Package Manager for core modules, provider modules, and the CLI.
- SwiftUI and AppKit integration where needed for a first-class macOS app.
- macOS 15 as the minimum deployment target. Mimicry is intentionally not looking backward unless a narrow compatibility shim is cheap and safe.
- Xcode as the main IDE, debugger, Instruments entry point, and UI test runner.
- XcodeGen with `project.yml` so the Xcode project is reproducible and avoids noisy `.xcodeproj` churn.
- GitHub Actions on macOS runners for build, unit test, and CLI validation.
- Codex for implementation passes, code review passes, documentation updates, and phase-by-phase issue breakdown.

Recommended Swift packages and frameworks:

- `swift-argument-parser` for the CLI command tree.
- Swift Testing for new model, provider, validation, and serialization tests.
- XCTest where app-hosted, UI, or older Xcode integration tests need it.
- `OSLog` for native unified logging in the app.
- A small internal logging facade in `MimicryCore` so CLI and GUI can share structured action logs.
- Foundation `Codable` for snapshot JSON.
- CryptoKit for checksums, signatures, and future optional encrypted snapshot sections.

Tools to avoid unless a provider has a strong reason:

- Electron or other cross-platform UI frameworks.
- Python, Node.js, or shell scripts as the primary implementation.
- Private macOS APIs.
- Raw shell commands scattered through app code.
- Unversioned preference dumps.

Useful references:

- Apple SwiftUI documentation: https://developer.apple.com/documentation/swiftui/
- Swift Package Manager documentation: https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/
- Swift Argument Parser documentation: https://apple.github.io/swift-argument-parser/documentation/argumentparser/
- Apple Swift Testing documentation: https://developer.apple.com/documentation/Testing
- XcodeGen project specification: https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md
- Apple configuration profile guidance: https://support.apple.com/guide/deployment/plan-your-configuration-profiles-dep9a318a393/web
- Apple OSLog documentation: https://developer.apple.com/documentation/os/oslog

## Architecture

Mimicry should be structured around a shared core with independently testable providers.

```text
Mimicry/
    Package.swift
    project.yml
    Sources/
        MimicryApp/
        MimicryCLI/
        MimicryCore/
        MimicryProviders/
    Tests/
        MimicryCoreTests/
        MimicryProviderTests/
        MimicryCLITests/
    UITests/
    Resources/
    Docs/
```

Core responsibilities:

- Snapshot schema and migrations.
- Provider protocols.
- Capability detection.
- Validation.
- Diff planning.
- Apply planning.
- Dry-run action generation.
- Structured logging.
- Security and secret classification.
- Command execution abstraction.
- File backup and rollback support.

App responsibilities:

- Native SwiftUI navigation for Snapshot, Apply, Compare, History, Settings, and Diagnostics.
- Snapshot inspection.
- Apply progress.
- Warnings and user-action prompts.
- Export and import flows.

CLI responsibilities:

- `mimicry snapshot`
- `mimicry inspect`
- `mimicry validate`
- `mimicry diff`
- `mimicry apply`
- `mimicry doctor`

The GUI and CLI must call the same underlying implementation. No duplicated behavior between app and CLI.

## Provider Model

Every provider should declare what it can detect, snapshot, validate, apply, and explain.

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

Each provider must classify data as:

- safe configuration
- potentially sensitive
- excluded
- user must review
- machine-specific
- hardware-specific
- managed
- unsupported

MVP providers:

- Environment and capabilities
- Homebrew
- Mac App Store through `mas`
- Finder basics
- Terminal basics
- iCloud state detection
- Safari bookmarks/configuration
- Chrome bookmarks
- Firefox bookmarks

Future providers:

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

## Snapshot Format

The snapshot format should be versioned, portable, inspectable, and human-readable.

Initial format: a macOS package bundle with the extension `.mimicry`.

```text
my-mac.mimicry/
    manifest.json
    snapshot.json
    logs/
    browser/
    applications/
    encrypted/
    checksums.json
    README.md
```

Minimum metadata:

- schema version
- Mimicry version
- created timestamp
- source macOS version
- source architecture
- hardware model
- provider versions
- compatibility notes
- excluded sensitive-data report
- checksums

The snapshot must not contain passwords, tokens, cookies, private keys, browser session data, Keychain contents, or cloud credentials by default.

### Export Container Decision

Begin with a package bundle rather than a plain directory or compressed archive.

Package bundle benefits:

- Appears as a single file-like artifact in Finder.
- Can be opened by Mimicry through a custom document type.
- Keeps internal JSON, logs, browser files, encrypted sections, and checksums inspectable during development.
- Avoids compression/extraction friction during early schema migration work.
- Leaves room to mark it as a document package in the app's exported Uniform Type Identifier.

Package bundle tradeoffs:

- Not as convenient for transfer through tools that expect a single byte stream.
- Can be partially copied if moved by low-level tools incorrectly.
- Needs checksums so Mimicry can detect missing or modified internal files.

Plain directory tradeoffs:

- Easiest to inspect and generate.
- Least polished for users.
- Too easy to accidentally separate internal files from the snapshot.

Compressed archive tradeoffs:

- Best for transfer, sharing, and immutable export.
- Less convenient for inspection, diffing, partial repair, and migration.
- Better as a later `mimicry export --archive` option than the primary working format.

Decision: `.mimicry` starts as an inspectable package bundle. Add compressed export/import once the schema and checksum model have stabilized.

### Encryption Decision

Encrypted optional snapshot sections are part of the MVP.

MVP encryption should be explicit and opt-in. The normal snapshot remains secret-free. If a provider supports a sensitive-but-useful setting later, Mimicry can place that section under `encrypted/` with clear user approval, strong warnings, checksums, and a separate restore path. No provider may silently place secrets in either the normal snapshot or encrypted sections.

## Delivery Plan

### Phase 0: Discovery and Decisions

Goal: turn the prompt into concrete engineering decisions before scaffolding too much code.

Deliverables:

- Inspect `mac-os-playbook` and identify concepts to preserve, discard, or defer.
- Decide minimum deployment target after checking required APIs.
- Confirm Swift 6, SwiftUI, SwiftPM, and XcodeGen project shape.
- Draft provider list and dependency policy.
- Create initial issues or task list for phases 1 through 6.

Exit criteria:

- Architecture is agreed.
- MVP provider list is agreed.
- Known risky areas are documented.

### Phase 1: Scaffold, Core Contracts, CLI, UI Shell

Goal: create a compiling native project with the shared core in place.

Deliverables:

- `Package.swift` with library and executable targets.
- `project.yml` for XcodeGen.
- SwiftUI app target with empty navigation shell.
- CLI target with command placeholders.
- Core models for snapshots, providers, validation, planned actions, apply results, and logs.
- `.mimicry` package-bundle reader/writer with manifest, checksum, and optional encrypted-section placeholders.
- `CommandRunner` abstraction with a fake implementation for tests.
- Initial documentation stubs in `Docs/`.

Exit criteria:

- `swift build` passes.
- `swift test` passes.
- Xcode project generates.
- App launches.
- `mimicry --help` works.

### Phase 2: Capability Detection, Homebrew, App Store, Doctor

Goal: produce useful local diagnostics and first real snapshot sections.

Deliverables:

- `MacCapabilities` detection for macOS version, architecture, hardware, admin status, CLT, Xcode, Homebrew, `mas`, iCloud state, App Store state, FileVault, SIP, and MDM/profile hints.
- Homebrew provider for taps, formulae, casks, prefix, and architecture.
- App Store provider using `mas` where available.
- `mimicry doctor` with PASS/WARN/INFO/BLOCKED output.
- Snapshot generation for environment, Homebrew, and App Store sections.

Exit criteria:

- Doctor output is useful on the current Mac.
- Homebrew and App Store providers have unit tests with mocked commands.
- Missing Homebrew or `mas` is reported as a warning, not a crash.

### Phase 3: Finder, Terminal, iCloud

Goal: cover the first user-visible macOS configuration areas.

Deliverables:

- Finder provider for as many stable, reproducible preferences as can be safely detected, validated, and reapplied.
- Terminal provider for shell metadata and reviewed shell configuration files, covering as much as can be safely classified.
- Secret scanner for shell/profile files.
- iCloud provider that detects state and reports required user action without copying authentication.
- Snapshot inspection for captured, excluded, unsupported, and user-action-required items.

Exit criteria:

- Terminal provider refuses or redacts likely secrets by default.
- Finder provider documents every `defaults` or public mechanism it uses.
- iCloud provider never stores credentials or auth state.

### Phase 4: Browser Providers

Goal: support safe browser state without copying private profiles.

Deliverables:

- Safari provider with iCloud-aware bookmark/configuration strategy.
- Chrome provider with multi-profile bookmark support.
- Firefox provider with multi-profile bookmark support.
- Browser snapshot inspection and restore planning.
- Tests using fixture bookmark files.

Exit criteria:

- No provider copies cookies, passwords, browser tokens, sessions, or profile encryption keys.
- Bookmark imports are idempotent in dry-run planning.
- Multiple profiles are visible and reviewable.

### Phase 5: Diff, Dry Run, Apply, Backups, Rollback

Goal: make Mimicry a reconciliation tool, not just an inventory tool.

Deliverables:

- Diff engine comparing a snapshot to the current Mac.
- Dry-run planner with INSTALL, CONFIGURE, SKIP, BLOCKED, and REQUIRES USER ACTION groups.
- Apply engine for Homebrew, App Store, Finder, Terminal, and browser MVP providers.
- Pre-change backup strategy for mutable files/preferences.
- Operation log and partial rollback support where feasible.
- Opt-in encrypted section support for providers that have an explicitly approved sensitive payload.
- Idempotency tests for repeated apply planning.

Exit criteria:

- `mimicry apply snapshot --dry-run` changes nothing.
- Reapplying the same snapshot does not duplicate package installs, bookmarks, or configuration.
- Failed individual actions do not abort the whole apply unless marked fatal.
- Rollback limitations are documented.

### Phase 6: Hardening, UI Completion, Compatibility, Documentation

Goal: make the MVP trustworthy enough to use on real Macs.

Deliverables:

- Full SwiftUI flows for Snapshot, Apply, Compare, History, Settings, and Diagnostics.
- Compatibility metadata for provider settings.
- MDM/managed-setting reporting.
- Structured log export.
- Comprehensive docs: `ARCHITECTURE.md`, `SNAPSHOT-FORMAT.md`, `SECURITY.md`, `PROVIDERS.md`, `DEVELOPMENT.md`, `TESTING.md`, and `COMPATIBILITY.md`.
- GitHub Actions build and test workflow.
- Manual test checklist for reference and destination Macs.

Exit criteria:

- All MVP workflows are documented.
- Tests pass locally and in CI.
- Manual test on at least one real Mac is complete.
- Known limitations are visible to users.

## First Implementation Slice

The first code change should be intentionally small:

1. Add `Package.swift`.
2. Add `project.yml`.
3. Create `MimicryCore` with snapshot, provider, log, and command-runner models.
4. Create `MimicryCLI` with `doctor`, `snapshot`, `inspect`, `validate`, `diff`, and `apply` command shells.
5. Create a SwiftUI app shell with sidebar navigation.
6. Add tests for snapshot encoding and fake command execution.

That slice proves the architecture without touching real system settings.

## Safety Rules

Mimicry must always tell the user:

- what was captured
- what can be restored
- what was excluded
- what is hardware-specific
- what is macOS-version-specific
- what requires authentication
- what is managed by MDM
- what is unsupported
- what changed
- why it changed

Mimicry must never:

- store Apple Account credentials
- store passwords
- copy Keychain contents
- copy private keys
- copy browser cookies or session tokens
- bypass macOS authentication
- bypass MDM
- claim complete macOS reproduction without explicit provider support and tests

## Privileged Helper Policy

A privileged helper means a separate helper executable, usually a LaunchDaemon, that runs with elevated privileges and performs operations the normal app or CLI cannot safely perform as the current user.

Mimicry should not start with a persistent privileged helper. The MVP should prefer:

- user-context actions whenever possible
- documented Apple APIs
- explicit user approval
- clear manual instructions where macOS requires a human step
- one-shot authorization or `sudo`-style CLI workflows only when a provider genuinely requires it

Reasons to avoid a helper in the MVP:

- It increases signing, entitlement, install, update, and uninstall complexity.
- It expands the security review surface.
- It can make users nervous because it adds a root-capable background component.
- Many MVP actions, including Homebrew, App Store detection, Finder preferences, Terminal files, bookmarks, dry-run planning, and snapshot inspection, do not need a root daemon.

When a privileged helper becomes necessary, it should use the modern Service Management model with helper resources inside the app bundle, registered through `SMAppService`, and controlled through System Settings approval. The helper must expose a narrow XPC API, never accept raw shell strings, log every privileged action, and be optional unless the selected provider requires it.

Candidate post-MVP helper use cases:

- system-wide settings that require root
- installing or managing LaunchDaemons
- managed backup/rollback of protected files
- system-level configuration profile workflows where appropriate
- carefully scoped operations that cannot be expressed safely through user-context commands

## Resolved Decisions

- Minimum macOS deployment target: macOS 15.
- `.mimicry` export format: start as an inspectable macOS package bundle; add compressed archive export later.
- App and CLI shipping model: together for now. The CLI should live with the app bundle or be installed from it, but share the same core implementation.
- Privileged helper support: avoid a persistent helper in the MVP. Add one later only when a provider proves it needs root-level background capability.
- Finder and Terminal scope: capture and apply as much as possible, but only when each setting is explicitly classified, validated, backed up where practical, and covered by tests.
- Encrypted optional snapshot sections: MVP, opt-in, and never a license to silently capture secrets.
