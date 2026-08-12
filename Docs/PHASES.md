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

Status: Done.

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

## Phase 3: End-To-End Trust Loop

Status: Done.

Goal: make the existing providers manually testable as a real workflow before adding more provider breadth.

Deliverables:

- Finder provider for as many stable, reproducible preferences as can be safely detected, validated, and reapplied.
- Terminal provider for shell metadata and reviewed shell configuration files, covering as much as can be safely classified.
- Secret scanner for shell/profile files.
- iCloud provider that detects state and reports required user action without copying authentication.
- Snapshot inspection for captured, excluded, unsupported, and user-action-required items.
- Snapshot diff for the current Mac.
- Dry-run apply planning for existing providers.
- First narrow safe apply path with backups, explicit confirmation, and fake-runner mutation tests.

Vertical slices:

- Slice A, Trust The Snapshot: `snapshot`, `validate`, and rich `inspect` make captured, excluded, redacted, unsupported, and review-required items visible.
- Slice B, Explain The Difference: `diff` compares an existing snapshot with the current Mac and reports matching, changed, missing, current-only, skipped, and unsupported items.
- Slice C, Dry-Run Apply: `apply --dry-run` produces a real action plan without mutating this Mac.
- Slice D, First Safe Apply: enables a confirmed Finder-only mutation path for safe boolean/string preferences, with a pre-write backup and clear limitations.

Exit criteria:

- Terminal provider refuses or redacts likely secrets by default.
- Finder provider documents every `defaults` or public mechanism it uses.
- iCloud provider never stores credentials or auth state.
- A user can run `doctor`, `snapshot`, `inspect`, `diff`, `apply --dry-run`, and the narrow `apply --confirm` path and understand the result without opening JSON.
- The first real apply behavior is narrow, backed up where practical, and covered by tests.

## Phase 4: Browser Providers

Status: Done for the review-first browser provider phase. Phase 4A adds read-only Safari bookmark inventory, Phase 4B adds read-only multi-profile Chrome bookmark inventory, Phase 4C adds read-only multi-profile Firefox bookmark inventory, Phase 4D adds browser-specific dry-run restore planning, Phase 4E adds a reviewable browser bookmark export handoff, and Phase 4F links dry-run browser previews to the exact export command. These browser slices include fixture coverage, URL query/fragment redaction, idempotency-aware planning by sanitized bookmark fingerprint, and manual browser-native import artifacts without profile mutation. Direct browser profile mutation remains intentionally deferred beyond Phase 4.

Goal: support safe browser state without copying private profiles.

Deliverables:

- Safari provider with iCloud-aware bookmark/configuration strategy. Read-only bookmark inventory, dry-run import planning, and HTML export handoff are implemented; iCloud account handling and direct profile import remain deferred because Mimicry does not copy private browser profiles.
- Chrome provider with multi-profile bookmark support. Read-only multi-profile bookmark inventory, dry-run import planning, and HTML export handoff are implemented; direct profile import remains deferred because Mimicry does not copy private browser profiles.
- Firefox provider with multi-profile bookmark support. Read-only multi-profile bookmark inventory, dry-run import planning, and HTML export handoff are implemented; direct profile import remains deferred because Mimicry does not copy private browser profiles.
- Browser snapshot inspection and restore planning. Dry-run restore planning is implemented for bookmark fingerprints; dry-run output now points to the HTML export command for manual import while profile mutation remains deferred.
- Tests using fixture bookmark files.

Exit criteria:

- No provider copies cookies, passwords, browser tokens, sessions, or profile encryption keys.
- Bookmark imports are idempotent in dry-run planning.
- Multiple profiles are visible and reviewable.
- Browser bookmark restore can proceed through a reviewed HTML handoff without Mimicry writing browser profile files.

## Phase 5: Broader Apply, Backups, Rollback

Goal: broaden the reconciliation engine after the first end-to-end loop exists.

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

Status: In progress for the GUI. The first polish slice replaced the Phase 1 placeholder with a native dashboard-style SwiftUI shell, section-specific Snapshot/Apply/Compare/History/Diagnostics surfaces, a Settings scene, and app smoke/content tests. Phase 6A wires the app to the existing snapshot engine for package creation, local diagnostics refresh, and recent package history. Phase 6B opens existing `.mimicry` packages, validates package contents through the core package store, and surfaces source metadata, section summaries, warnings, and safety/review/excluded/unsupported counts in Snapshot and History. Phase 6C compares an open package with the current Mac through the existing diff engine and renders matching, changed, missing, current-only, skipped, and blocked groups. Phase 6D previews the existing non-mutating dry-run apply plan from the Apply tab, including install, configure, skip, blocked, and user-action groups. Phase 6E exports a reviewable browser bookmark HTML handoff from the Apply tab without touching browser profiles. Phase 6F runs the backed-up Finder-safe confirmed apply path from the Apply tab after dry-run review. Phase 6G records GUI workflow audit events and exports them as structured JSON from History.

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
