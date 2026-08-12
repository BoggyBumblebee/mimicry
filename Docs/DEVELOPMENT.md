# Development

## Toolchain

Primary tools:

- Swift 6 and Swift Package Manager for core modules, provider modules, and the CLI.
- SwiftUI and AppKit integration where needed for a first-class macOS app.
- macOS 15 as the minimum deployment target.
- App identity: `Mimicry`, bundle identifier `com.boggybumblebee.mimicry`, CLI executable `mimicry`.
- Xcode as the main IDE, debugger, Instruments entry point, and UI test runner.
- XcodeGen with `project.yml` so the Xcode project is reproducible and avoids noisy `.xcodeproj` churn.
- GitHub Actions on macOS runners for build, unit test, CLI validation, and SonarCloud analysis.
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

## Project Generation

Commit `project.yml`. Generate the Xcode project locally:

```bash
xcodegen generate
```

Do not treat generated `.xcodeproj` churn as the source of truth.

## CI

GitHub Actions runs on macOS runners and validates:

- Swift toolchain availability.
- SwiftPM tests.
- XcodeGen project generation.
- Xcode test scheme with repo-local DerivedData.
- SonarCloud analysis using `sonar-project.properties`, Xcode coverage, and generic test-execution reports.

SonarCloud requires a repository secret named `SONAR_TOKEN`. The SonarCloud project key is `BoggyBumblebee_mimicry`.

## Xcode Signing and Distribution Setup

Mimicry should be distributed outside the Mac App Store as a Developer ID signed and notarized macOS app. The Mac App Store sandbox is a poor fit because Mimicry needs to inspect local applications, shell files, package manager state, browser files, preferences, and system configuration.

Development setup:

1. Use Xcode with the Apple Developer account signed in under Xcode > Settings > Accounts.
2. Use the bundle identifier `com.boggybumblebee.mimicry`.
3. Set the macOS deployment target to `15.0`.
4. Use automatic signing for local development if it keeps iteration smooth.
5. Keep App Sandbox disabled for the MVP.
6. Enable Hardened Runtime for Release builds.
7. Do not enable overly broad entitlements preemptively. Add capabilities only when a provider proves it needs them.

Developer ID release setup:

1. Ensure the Apple Developer account has a Developer ID Application certificate available.
2. If an installer package is introduced later, also create a Developer ID Installer certificate.
3. Archive the app in Xcode.
4. Open Window > Organizer.
5. Select the archive and choose Distribute App.
6. Select Developer ID as the distribution method.
7. Upload for notarization through Xcode's workflow.
8. Export the notarized app.
9. Verify the exported app on a clean macOS account or machine before publishing.

Automated release setup can come later with `notarytool` and `stapler`, but the first release path should use Xcode Organizer so signing, Hardened Runtime, and notarization failures are visible while the project is still young.

## CLI Shipping

- Ship the CLI with the app for now.
- The CLI should use the same `MimicryCore` implementation as the app.
- The app can later offer to install or update a symlink such as `/usr/local/bin/mimicry` or `~/.local/bin/mimicry`.
- The symlink flow must explain what it changes and ask before modifying a shell-accessible location.

## References

- Apple SwiftUI documentation: https://developer.apple.com/documentation/swiftui/
- Swift Package Manager documentation: https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/
- Swift Argument Parser documentation: https://apple.github.io/swift-argument-parser/documentation/argumentparser/
- Apple Swift Testing documentation: https://developer.apple.com/documentation/Testing
- XcodeGen project specification: https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md
- Apple configuration profile guidance: https://support.apple.com/guide/deployment/plan-your-configuration-profiles-dep9a318a393/web
- Apple OSLog documentation: https://developer.apple.com/documentation/os/oslog
- Apple Developer ID certificate guidance: https://developer.apple.com/help/account/certificates/create-developer-id-certificates
- Apple notarization guidance: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
