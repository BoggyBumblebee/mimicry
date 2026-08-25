# Mimicry

[![CI](https://github.com/BoggyBumblebee/mimicry/actions/workflows/ci.yml/badge.svg)](https://github.com/BoggyBumblebee/mimicry/actions/workflows/ci.yml)
[![SonarCloud Quality Gate](https://sonarcloud.io/api/project_badges/measure?project=BoggyBumblebee_mimicry&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=BoggyBumblebee_mimicry)
[![SonarCloud Coverage](https://sonarcloud.io/api/project_badges/measure?project=BoggyBumblebee_mimicry&metric=coverage)](https://sonarcloud.io/summary/new_code?id=BoggyBumblebee_mimicry)

Mimicry helps make moving between Apple macOS devices as seamless as possible, and helps keep a user's Macs consistent in the tools, configuration, and usability details that make a machine feel ready to work on.

The core workflow is:

```text
Snapshot a known-good Mac.
Inspect exactly what was captured and excluded.
Apply that snapshot to another Mac safely, repeatably, and with clear explanations.
```

Mimicry is not a backup tool, disk clone, or credential migration utility. It should never try to copy an entire home directory, browser profile, Keychain, or `~/Library` tree. Its job is to capture the parts of a Mac setup that can be safely understood, reviewed, and reapplied so another Mac can feel familiar without dragging private state or machine-specific baggage along with it.

The full build prompt is tracked in [PROMPT.md](PROMPT.md).

## Current Status

Phase 0, Phase 1, Phase 2, Phase 3, and Phase 4 are done. Phase 4 completed the review-first browser provider path with read-only Safari, Chrome, and Firefox bookmark inventory, browser-specific dry-run restore planning, a reviewable browser bookmark export handoff, and dry-run guidance that points directly to that handoff. Mimicry can create, validate, richly inspect, diff, dry-run apply, export sanitized browser bookmarks, and perform the first narrow confirmed apply from a `.mimicry` snapshot package containing environment, Homebrew, App Store, Finder, Terminal, iCloud, Safari, Chrome, and Firefox sections.

Current scaffold includes:

- Swift package with `MimicryCore`, `MimicryCLISupport`, and `mimicry` CLI targets.
- XcodeGen configuration in `project.yml`.
- Native SwiftUI dashboard with Snapshot, Apply, Compare, History, Diagnostics, and Settings surfaces reflecting the current safe workflow. The app can create `.mimicry` snapshot packages through the existing core snapshot engine from the toolbar or Package menu, open existing packages from the same global actions, keep the Snapshot section focused on package review, expand captured sections to inspect items and warnings, group Homebrew package review into Config, Taps, Formulae, and Casks branches, summarize safety and compatibility counts, compare an open package with the current Mac, preview a non-mutating dry-run apply plan with managed and machine-specific review signals while keeping environment metadata informational, run the backed-up Finder-safe confirmed apply path after dry-run review, export a reviewable browser bookmark HTML handoff from an open package, export a structured JSON audit log from History, refresh local diagnostics with management detail, and remember recent packages.
- CLI command shells, with `mimicry doctor` reporting read-only local diagnostics, `mimicry snapshot` writing the first real package sections, `mimicry inspect` rendering a human-readable audit of captured, review-required, excluded, unsupported, and warning items, `mimicry diff` comparing a snapshot to the current Mac, `mimicry apply --dry-run` rendering action plans including browser bookmark import previews and the exact export handoff command when browser work is present, `mimicry export-browser-bookmarks` writing a reviewable browser-import HTML handoff, and `mimicry apply --confirm` applying only explicitly safe Finder boolean/string preferences with a backup.
- Core snapshot, provider, log, command-runner, and `.mimicry` package models.
- Capability detection, Phase 2 providers for environment, Homebrew, and App Store inventory, Phase 3 providers for Finder, Terminal, and iCloud inventory, and Phase 4 Safari, Chrome, and Firefox bookmark inventory providers.
- Unit tests for snapshot JSON, package checksums, fake command execution, provider registry, capabilities, providers, snapshot building, dry-run planning, browser bookmark export, confirmed Finder apply behavior, CLI smoke behavior, and app shell smoke/content behavior.
- GitHub Actions workflow for macOS validation.
- SonarCloud configuration, coverage conversion, and README quality badges.

Most commands remain non-mutating. Environment metadata such as hardware model, hostname, and username is captured for provenance and review, but dry-run apply treats the environment section as informational and never plans to apply it to another Mac. Safari, Chrome, and Firefox bookmarks are read-only and review-required; bookmark URL query strings and fragments are removed during capture, dry-run planning summarizes importable, already-present, skipped, and blocked bookmark work, and browser dry-run output recommends the exact `export-browser-bookmarks` command for a reviewable HTML handoff. Mimicry still does not write browser profiles, browser databases, cookies, passwords, sessions, or browser account state; direct browser profile mutation is intentionally outside the completed Phase 4 scope. The only current mutation path is the Finder-safe confirmed apply flow, available through `mimicry apply --confirm` and the app Apply tab after dry-run review. It is intentionally limited to safe Finder preferences, writes a backup first when changes are required, and does not delete preferences or copy user-specific values.

## Documentation

- [Architecture](Docs/ARCHITECTURE.md): module layout, app/CLI/core boundaries, provider architecture, and first implementation slice.
- [Snapshot Format](Docs/SNAPSHOT-FORMAT.md): `.mimicry` package bundle, manifest, checksums, and encryption placeholders.
- [Security](Docs/SECURITY.md): secrets policy, encryption, sandbox decision, privileged helper policy, and user-approval rules.
- [Providers](Docs/PROVIDERS.md): provider model, MVP providers, future providers, and provider safety classifications.
- [Development](Docs/DEVELOPMENT.md): Swift/Xcode/XcodeGen workflow, project generation policy, signing setup, and Codex collaboration.
- [Testing](Docs/TESTING.md): validation commands, expected coverage areas, and test boundaries.
- [Compatibility](Docs/COMPATIBILITY.md): macOS 15 target, hardware applicability, managed Macs, and version compatibility.
- [Phase Plan](Docs/PHASES.md): phase-by-phase delivery plan and exit criteria.
- [Completion Log](Docs/COMPLETION-LOG.md): completed setup, implementation, documentation, quality, and validation steps.
- [License](LICENSE.md): MIT License terms.

## Codex Collaboration

This project is being planned and built with Codex as an implementation partner.

Codex was used in the creation of this project, including planning, documentation, implementation, validation, and repository maintenance.

Future implementation work should continue to make Codex-generated changes easy to review: small commits, explicit phase boundaries, tests with each meaningful behavior change, quality and coverage gates before commits, and documentation updates whenever the architecture or supported behavior changes.

## Progress Tracking

Completion-log updates are part of the definition of done.

At each and every completed step, phase, or meaningful implementation slice, update the completion log before the work is considered complete. The update should record:

- what was completed
- the completion date
- the validation performed
- any limitations, follow-up work, or intentionally deferred behavior

The completion log should stay concise and now lives in [Docs/COMPLETION-LOG.md](Docs/COMPLETION-LOG.md). It intentionally does not duplicate Git commit SHAs; Git remains the source of truth for exact revision history. Detailed technical documentation lives in `Docs/`, and the README remains the visible project map.

## Product Goal

Mimicry exists to replace the fragile parts of an Ansible-style Mac setup workflow with a modern macOS-native app. It should preserve the useful intent of a playbook: applications, Homebrew packages, App Store apps, shell setup, Finder preferences, browser bookmarks, and user-visible configuration. It should discard the unsafe parts: blindly copying files, storing credentials, bypassing macOS authentication, and assuming settings still work across macOS releases.

The target outcome is:

```bash
mimicry snapshot --output ~/Desktop/primary-mac.mimicry
mimicry doctor
mimicry apply ~/Desktop/primary-mac.mimicry --dry-run
mimicry export-browser-bookmarks ~/Desktop/primary-mac.mimicry --output ~/Desktop/mimicry-browser-bookmarks.html
mimicry apply ~/Desktop/primary-mac.mimicry --confirm
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

Run the current non-mutating doctor diagnostics:

```bash
swift run mimicry doctor
```

Create a read-only snapshot package:

```bash
swift run mimicry snapshot --output ~/Desktop/primary-mac.mimicry
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

Run the current manual trust loop:

```bash
swift run mimicry doctor
swift run mimicry snapshot --output ~/Desktop/manual-test.mimicry
swift run mimicry validate ~/Desktop/manual-test.mimicry
swift run mimicry inspect ~/Desktop/manual-test.mimicry
swift run mimicry diff ~/Desktop/manual-test.mimicry
swift run mimicry apply ~/Desktop/manual-test.mimicry --dry-run
swift run mimicry export-browser-bookmarks ~/Desktop/manual-test.mimicry --output ~/Desktop/mimicry-browser-bookmarks.html
```

When browser bookmark work is present, the dry-run output includes a `Browser Bookmark Handoff` section with the matching export command and a default `mimicry-browser-bookmarks.html` output path. Review the generated Netscape-style HTML file before importing it manually in a browser; Mimicry does not write browser profile files directly.

The current real apply path is deliberately narrow and should be run only after reviewing the dry-run output:

```bash
swift run mimicry apply ~/Desktop/manual-test.mimicry --confirm
```

`--confirm` only considers safe Finder boolean/string preferences, writes a backup of the current Finder section before changing anything, skips user-specific values such as paths, and never deletes preferences.

## License

Distributed under the MIT License. See [LICENSE.md](LICENSE.md) for details.
