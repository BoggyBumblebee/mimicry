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

## Current Status

Phase 0 is done. Phase 1 is in progress, with the first non-mutating scaffold slice complete.

Current scaffold includes:

- Swift package with `MimicryCore` and `mimicry` CLI targets.
- XcodeGen configuration in `project.yml`.
- SwiftUI app shell.
- CLI command shells.
- Core snapshot, provider, log, command-runner, and `.mimicry` package models.
- Unit tests for snapshot JSON, package checksums, and fake command execution.

No current code mutates system settings.

## Documentation

- [Architecture](Docs/ARCHITECTURE.md): module layout, app/CLI/core boundaries, provider architecture, and first implementation slice.
- [Snapshot Format](Docs/SNAPSHOT-FORMAT.md): `.mimicry` package bundle, manifest, checksums, and encryption placeholders.
- [Security](Docs/SECURITY.md): secrets policy, encryption, sandbox decision, privileged helper policy, and user-approval rules.
- [Providers](Docs/PROVIDERS.md): provider model, MVP providers, future providers, and provider safety classifications.
- [Development](Docs/DEVELOPMENT.md): Swift/Xcode/XcodeGen workflow, project generation policy, signing setup, and Codex collaboration.
- [Testing](Docs/TESTING.md): validation commands, expected coverage areas, and test boundaries.
- [Compatibility](Docs/COMPATIBILITY.md): macOS 15 target, hardware applicability, managed Macs, and version compatibility.
- [Phase Plan](Docs/PHASES.md): phase-by-phase delivery plan and exit criteria.

## Codex Collaboration

This project is being planned and built with Codex as an implementation partner.

Codex has been used to:

- initialize the repository
- create and push the GitHub project
- import the original build prompt as `PROMPT.md`
- inspect related BoggyBumblebee projects
- turn the build prompt into an implementation roadmap
- capture architecture, tooling, safety, and delivery decisions before coding began
- scaffold the first non-mutating Phase 1 implementation slice

Future implementation work should continue to make Codex-generated changes easy to review: small commits, explicit phase boundaries, tests with each meaningful behavior change, and documentation updates whenever the architecture or supported behavior changes.

## Progress Tracking

README status updates are part of the definition of done.

At each and every completed step, phase, or meaningful implementation slice, update this README before the work is considered complete. The update should record:

- what was completed
- the completion date
- the commit SHA, once available
- the validation performed
- any limitations, follow-up work, or intentionally deferred behavior

The completion log should stay concise. Detailed technical documentation lives in `Docs/`, but the README remains the visible project map.

## Completion Log

| Date | Step | Status | Commit | Validation |
| --- | --- | --- | --- | --- |
| 2026-08-12 | Repository setup and prompt import | Done | `927b8cf` | `PROMPT.md` imported, committed, and pushed to `origin/main` |
| 2026-08-12 | Phase 0: Discovery and decisions | Done | `d434a0b` | Roadmap, toolchain, Xcode distribution setup, safety rules, open decisions, and resolved decisions documented and pushed to `origin/main` |
| 2026-08-12 | Phase 1 scaffold slice: Swift package, XcodeGen config, SwiftUI shell, CLI shell, core models, `.mimicry` package store, fake command runner, and tests | Done | `a5289a3` | `swift test`, `xcodegen generate`, `xcodebuild ... build`, `xcodebuild ... test`, `swift run mimicry --help`, `swift run mimicry doctor` |
| 2026-08-12 | Documentation split: README map plus focused docs under `Docs/` | Done | `98b7297` | README and docs reorganized; links and status checked |

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

## Resolved Decisions

- Minimum macOS deployment target: macOS 15.
- App identity: `Mimicry`, bundle identifier `com.boggybumblebee.mimicry`, CLI executable `mimicry`.
- App sandbox: disabled for MVP.
- Distribution: Developer ID signed and notarized app outside the Mac App Store.
- `.mimicry` export format: start as an inspectable macOS package bundle; add compressed archive export later.
- App and CLI shipping model: together for now.
- CLI install behavior: app-bundled CLI first, optional symlink installer later for `/usr/local/bin/mimicry` or `~/.local/bin/mimicry`.
- Privileged helper support: avoid a persistent helper in the MVP. Add one later only when a provider proves it needs root-level background capability.
- Finder and Terminal scope: capture and apply as much as possible, but only when each setting is explicitly classified, validated, backed up where practical, and covered by tests.
- Encrypted optional snapshot sections: MVP, opt-in, passphrase-based, and never a license to silently capture secrets.
- Project generation: commit `project.yml`; generate the Xcode project in the normal local workflow rather than treating generated project churn as the source of truth.
- Documentation split: keep README as the map and move deep detail into `Docs/`.
- First implementation slice: no real system mutation. Build skeleton, models, CLI shell, package reader/writer, and tests first.

## Quick Start

Run the current non-mutating CLI shell:

```bash
swift run mimicry doctor
```

Generate the Xcode project:

```bash
xcodegen generate
```

Run tests:

```bash
swift test
xcodebuild -project Mimicry.xcodeproj -scheme Mimicry -destination platform=macOS -derivedDataPath .build/XcodeDerivedData test CODE_SIGNING_ALLOWED=NO
```
