# Phase Plan

Do not attempt to implement the entire application in one giant change.

## Phase 0: Discovery and Decisions

Status: Done.

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

## Phase 1: Scaffold, Core Contracts, CLI, UI Shell

Status: Done.

Goal: create a compiling native project with the shared core in place.

Deliverables:

- `Package.swift` with library and executable targets.
- `project.yml` for XcodeGen.
- SwiftUI app target with empty navigation shell.
- CLI target with command placeholders.
- Core models for snapshots, providers, validation, planned actions, apply results, and logs.
- `.mimicry` package-bundle reader/writer with manifest, checksum, and optional encrypted-section placeholders.
- `CommandRunner` abstraction with a fake implementation for tests.
- Capability model and provider registry.
- Testable CLI support target.
- CLI smoke tests.
- macOS CI workflow.
- Initial focused documentation under `Docs/`.

Exit criteria:

- `swift build` passes.
- `swift test` passes.
- Xcode project generates.
- App launches.
- `mimicry --help` works.

## Phase 2: Capability Detection, Homebrew, App Store, Doctor

Status: In progress. Phase 2A doctor diagnostics are implemented; Homebrew/App Store snapshot providers are next.

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

## Phase 3: Finder, Terminal, iCloud

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

## Phase 4: Browser Providers

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

## Phase 5: Diff, Dry Run, Apply, Backups, Rollback

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

## Phase 6: Hardening, UI Completion, Compatibility, Documentation

Goal: make the MVP trustworthy enough to use on real Macs.

Deliverables:

- Full SwiftUI flows for Snapshot, Apply, Compare, History, Settings, and Diagnostics.
- Compatibility metadata for provider settings.
- MDM/managed-setting reporting.
- Structured log export.
- Comprehensive docs.
- GitHub Actions build and test workflow.
- Manual test checklist for reference and destination Macs.

Exit criteria:

- All MVP workflows are documented.
- Tests pass locally and in CI.
- Manual test on at least one real Mac is complete.
- Known limitations are visible to users.
