# Testing

Build automated tests from the beginning.

## Current Validation Commands

```bash
swift test
xcodegen generate
xcodebuild -project Mimicry.xcodeproj -scheme Mimicry -destination platform=macOS -derivedDataPath .build/XcodeDerivedData build CODE_SIGNING_ALLOWED=NO
xcodebuild -project Mimicry.xcodeproj -scheme Mimicry -destination platform=macOS -derivedDataPath .build/XcodeDerivedData test CODE_SIGNING_ALLOWED=NO
swift run mimicry --help
swift run mimicry doctor
swift run mimicry snapshot --output /tmp/mimicry-phase2b-smoke.mimicry
swift run mimicry inspect /tmp/mimicry-phase2b-smoke.mimicry
swift run mimicry validate /tmp/mimicry-phase2b-smoke.mimicry
swift run mimicry diff /tmp/mimicry-phase2b-smoke.mimicry
swift run mimicry apply /tmp/mimicry-phase2b-smoke.mimicry --dry-run
swift run mimicry apply /tmp/mimicry-phase2b-smoke.mimicry --confirm
git diff --check
```

## SonarCloud Reports

The SonarCloud workflow generates an `.xcresult` bundle, converts line coverage to Sonar's generic coverage XML, and converts Xcode test results to Sonar's generic test-execution XML.

The Xcode scheme must gather coverage for every testable source module that SonarCloud counts. `MimicryCore` and `MimicryCLISupport` are both coverage targets, and `MimicryTests` plus `MimicryCLITests` both run under the scheme. `Sources/MimicryCLI/main.swift` is excluded from coverage because it is a thin ArgumentParser entry point; its behavior is validated by `swift run` smoke checks while command rendering and package behavior live in covered support modules.

```bash
mkdir -p BuildArtifacts
xcodebuild -project Mimicry.xcodeproj -scheme Mimicry -destination platform=macOS -derivedDataPath .build/DerivedData -resultBundlePath BuildArtifacts/Mimicry.xcresult test CODE_SIGNING_ALLOWED=NO
Scripts/xccov-to-sonar-generic.sh BuildArtifacts/Mimicry.xcresult BuildArtifacts/sonar-generic-coverage.xml
python3 Scripts/xcresult-to-sonar-test-execution.py BuildArtifacts/Mimicry.xcresult BuildArtifacts/sonar-test-execution.xml
```

For pre-commit coverage checks, use the converted Sonar XML as the authoritative local denominator:

```bash
awk '/lineToCover/ {total++; if ($0 ~ /covered="true"/) covered++} END {printf "%.2f%% (%d/%d)\n", covered/total*100, covered, total}' BuildArtifacts/sonar-generic-coverage.xml
```

The total must stay above 80%, preferably with meaningful headroom.

## Snapshot Tests

- snapshot schema
- serialization
- deserialization
- migration
- sensitive-data filtering
- package checksums
- package corruption detection
- snapshot builder writes environment, Homebrew, App Store, Finder, Terminal, iCloud, Safari, and Chrome sections

## Manual Trust Loop

The current end-to-end manual path begins read-only:

```bash
swift run mimicry doctor
swift run mimicry snapshot --output ~/Desktop/manual-test.mimicry
swift run mimicry validate ~/Desktop/manual-test.mimicry
swift run mimicry inspect ~/Desktop/manual-test.mimicry
swift run mimicry diff ~/Desktop/manual-test.mimicry
swift run mimicry apply ~/Desktop/manual-test.mimicry --dry-run
```

`inspect` should show package metadata, source Mac metadata, section totals, classification and applicability summaries, captured items, review-required items, excluded items, unsupported items, warnings, and the no-mutation statement.

For Safari, `inspect` should show a `safari` section when bookmarks are present or a warning/source item when they are absent or unreadable. Bookmark entries should be review-required and user-specific. URL query strings and fragments should not appear in captured Safari bookmark values.

For Chrome, `inspect` should show a `chrome` section when profile bookmarks are present or a warning/source item when they are absent or unreadable. Profile, folder, and bookmark entries should be review-required and user-specific. URL query strings and fragments should not appear in captured Chrome bookmark values.

`diff` should compare the snapshot to the current Mac and show matching, changed, missing, current-only, skipped, unsupported, snapshot-warning, and current-warning groups without mutating system settings.

`apply --dry-run` should render install, configure, skip, blocked, and requires-user-action groups without mutating system settings.

After reviewing the dry-run, the first real apply slice can be tested manually:

```bash
swift run mimicry apply ~/Desktop/manual-test.mimicry --confirm
```

`apply --confirm` only considers explicitly safe Finder boolean/string preferences, writes a backup of the current Finder section before changing anything, skips user-specific values such as Finder paths, never deletes preferences, and reports either applied results or that no safe Finder preference changes were required.

## Provider Tests

- Homebrew discovery
- App Store discovery
- Finder configuration discovery and absent-preference handling
- Safari bookmark parsing, missing bookmark handling, unreadable plist handling, and URL query/fragment redaction
- Chrome multi-profile bookmark parsing, missing profile handling, unreadable JSON handling, and URL query/fragment redaction
- Terminal configuration metadata and secret-like shell value redaction
- iCloud status metadata and authentication-state exclusion
- provider registry lookup and ordering
- capability model defaults
- capability detector command-output parsing with fake runners
- provider lifecycle methods that intentionally defer apply behavior to later phases
- secret scanner rules for private keys, token/password assignments, AWS access keys, and bearer tokens
- required-user-action behavior for providers that cannot apply authentication or account state

## CLI Tests

- root command exposes expected subcommands
- doctor output renders capability findings without mutating system state
- snapshot output summarizes the created `.mimicry` package
- inspect renders a human-readable audit of captured, review-required, excluded, unsupported, and warning items
- diff renders a human-readable comparison against the current snapshot
- apply dry-run renders a human-readable action plan
- non-dry-run apply without confirmation refuses to mutate system state
- confirmed apply renders the Finder-safe apply summary
- validate can read a fixture `.mimicry` package

## Compatibility Tests

- Apple Silicon vs Intel
- laptop vs desktop
- differing macOS versions

## Apply Tests

- dry-run planning
- confirmed safe Finder preference writes through fake command runners
- backup creation before confirmed Finder preference writes
- warning reporting for failed safe Finder preference writes
- idempotent no-op behavior when safe Finder preferences already match
- partial failure
- rollback behavior

## Security Tests

Verify that snapshots cannot accidentally contain:

- passwords
- private keys
- tokens
- browser credentials
- cookies
- browser sessions, history, autofill, website storage, profile encryption keys, extension auth state, and URL query/fragment secrets

## Test Boundary

Provider apply tests should use fakes, fixtures, and temporary directories. Manual real apply behavior must require explicit user confirmation and should begin with the narrow Finder-safe path.
