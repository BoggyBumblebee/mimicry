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
- snapshot builder writes environment, Homebrew, and App Store sections

## Provider Tests

- Homebrew discovery
- App Store discovery
- Finder configuration discovery and absent-preference handling
- browser bookmark parsing
- Terminal configuration metadata and secret-like shell value redaction
- provider registry lookup and ordering
- capability model defaults
- capability detector command-output parsing with fake runners
- provider lifecycle methods that intentionally defer apply behavior to later phases
- secret scanner rules for private keys, token/password assignments, AWS access keys, and bearer tokens

## CLI Tests

- root command exposes expected subcommands
- doctor output renders capability findings without mutating system state
- snapshot output summarizes the created `.mimicry` package
- inspect and validate can read a fixture `.mimicry` package
- remaining placeholder commands echo requested snapshot paths without mutating system state

## Compatibility Tests

- Apple Silicon vs Intel
- laptop vs desktop
- differing macOS versions

## Apply Tests

- idempotency
- dry run
- failure handling
- partial failure
- rollback behavior

## Security Tests

Verify that snapshots cannot accidentally contain:

- passwords
- private keys
- tokens
- browser credentials
- cookies

## Test Boundary

Early Phase 1 tests must not mutate system settings. Provider apply tests should use fakes, fixtures, and temporary directories until real provider behavior has explicit user approval and safety checks.
