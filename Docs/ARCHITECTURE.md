# Architecture

Mimicry is structured around a shared core with independently testable providers and thin app/CLI fronts.

```text
Mimicry/
    Package.swift
    project.yml
    Sources/
        MimicryApp/
        MimicryCLI/
        MimicryCLISupport/
        MimicryCore/
        MimicryProviders/
    Tests/
        MimicryCoreTests/
        MimicryCLITests/
        MimicryProviderTests/
    UITests/
    Resources/
    Docs/
```

## Boundaries

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

`MacCapabilitiesDetector` is the read-only diagnostics entry point. It uses `ProcessCommandRunner` in production and `FakeCommandRunner` in tests so command-probe behavior remains covered without running real system commands in unit tests.

`MimicrySnapshotBuilder` combines detected capabilities with the first read-only providers: environment, Homebrew, App Store, Finder, Terminal, and iCloud. It writes the resulting snapshot through `MimicryPackageStore` so CLI-created packages use the same package format as tests and future app workflows.

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

`MimicryCLISupport` owns deterministic response rendering so CLI behavior can be tested without shelling back into SwiftPM. `MimicryCLI` owns the ArgumentParser command definitions and executable entry point, then delegates behavior to shared support and core code.

## First Implementation Slice

The first implementation slice is intentionally non-mutating:

1. Add `Package.swift`.
2. Add `project.yml`.
3. Create `MimicryCore` with snapshot, provider, log, and command-runner models.
4. Create `MimicryCLI` with `doctor`, `snapshot`, `inspect`, `validate`, `diff`, and `apply` command shells.
5. Create a SwiftUI app shell with sidebar navigation.
6. Add a capabilities model and provider registry.
7. Add tests for snapshot encoding, package checksums, fake command execution, provider registry, capabilities, and CLI smoke behavior.
8. Add macOS CI for SwiftPM and Xcode project validation.

That slice proves the architecture without touching real system settings.

## Phase 2 Snapshot Slice

The Phase 2 snapshot slice keeps the same non-mutating boundary while producing useful inventory:

- environment metadata from detected capabilities
- Homebrew taps, formulae, casks, prefix, version, and architecture
- App Store applications through `mas list` when `mas` is available

Missing Homebrew or `mas` produces warnings in the snapshot section instead of crashing the command.

## Phase 3 Finder Slice

The first Phase 3 slice adds read-only Finder preference inventory. It uses the same command-runner abstraction as other providers, reads stable `com.apple.finder` keys through `defaults`, marks user-specific paths for review, and treats missing defaults as absent values rather than command failures.

## Phase 3 Terminal Slice

The Terminal slice adds shell metadata and reviewed shell configuration file metadata. It does not store shell file contents. A reusable secret scanner checks known shell profile files for private-key markers, token/password assignments, AWS access keys, and bearer tokens; files with secret-like findings are marked as redacted with rule IDs and finding counts only.

## Phase 3 iCloud Slice

The iCloud slice adds read-only status metadata from local capability state and the presence of the iCloud Drive container. It records whether user action is required and explicitly marks authentication state as excluded; it does not inspect account databases, tokens, sessions, synced documents, or credentials.

## Phase 3 End-To-End Slices

Phase 3 now prioritizes manually testable vertical slices over adding provider breadth. Slice A makes `inspect` the trust surface for snapshots: it reads the same package bundle that `snapshot` writes, summarizes classifications and applicability, groups captured, review-required, excluded, and unsupported items per section, surfaces warnings, and states that no system settings were changed.

## Existing Project Context

The implementation should learn from nearby BoggyBumblebee projects:

- [mac-os-playbook](https://github.com/BoggyBumblebee/mac-os-playbook): useful source of setup intent, including Homebrew packages, casks, App Store apps, dotfiles, Terminal configuration, Dock configuration, and post-provision hooks. Mimicry should not port this Ansible structure directly.
- [hodgepodge](https://github.com/BoggyBumblebee/hodgepodge): relevant Homebrew domain work, command execution, SwiftUI views, and XcodeGen project structure.
- [network-tools](https://github.com/BoggyBumblebee/network-tools): relevant SwiftUI service/model/view-model structure, validation patterns, logging utilities, unit tests, UI tests, and coverage-oriented schemes.
- [quickie](https://github.com/BoggyBumblebee/quickie): relevant lightweight macOS app structure, Swift 6 setup, app metadata, settings, launch-at-login patterns, and XcodeGen usage.
- [dotfiles](https://github.com/BoggyBumblebee/dotfiles): likely reference material for Terminal and shell providers, but never something to copy wholesale without secret scanning and explicit user review.

The broad pattern that fits Mimicry best is a native Swift project with a small, testable core and thin app/CLI fronts. Existing projects already show that XcodeGen plus SwiftUI works well in this workspace.
