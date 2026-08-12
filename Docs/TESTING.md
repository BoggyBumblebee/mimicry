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
