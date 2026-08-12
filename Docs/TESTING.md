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
git diff --check
```

## SonarCloud Reports

The SonarCloud workflow generates an `.xcresult` bundle, converts line coverage to Sonar's generic coverage XML, and converts Xcode test results to Sonar's generic test-execution XML.

```bash
mkdir -p BuildArtifacts
xcodebuild -project Mimicry.xcodeproj -scheme Mimicry -destination platform=macOS -derivedDataPath .build/DerivedData -resultBundlePath BuildArtifacts/Mimicry.xcresult test CODE_SIGNING_ALLOWED=NO
Scripts/xccov-to-sonar-generic.sh BuildArtifacts/Mimicry.xcresult BuildArtifacts/sonar-generic-coverage.xml
python3 Scripts/xcresult-to-sonar-test-execution.py BuildArtifacts/Mimicry.xcresult BuildArtifacts/sonar-test-execution.xml
```

## Snapshot Tests

- snapshot schema
- serialization
- deserialization
- migration
- sensitive-data filtering
- package checksums
- package corruption detection

## Provider Tests

- Homebrew discovery
- App Store discovery
- Finder configuration
- browser bookmark parsing
- Terminal configuration
- provider registry lookup and ordering
- capability model defaults
- capability detector command-output parsing with fake runners

## CLI Tests

- root command exposes expected subcommands
- doctor output renders capability findings without mutating system state
- inspect and validate can read a fixture `.mimicry` package
- placeholder commands echo requested snapshot paths without mutating system state

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
