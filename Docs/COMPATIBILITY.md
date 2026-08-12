# Compatibility

## macOS Target

Minimum macOS deployment target: macOS 15.

Mimicry is intentionally not looking backward unless a narrow compatibility shim is cheap and safe.

## Capability Detection

Phase 2A adds a read-only `MacCapabilitiesDetector` used by `mimicry doctor`. It combines Foundation/Darwin system metadata with safe command probes and does not mutate settings.

Current doctor diagnostics detect:

- macOS version
- architecture
- hardware model
- Apple Silicon vs Intel
- hostname
- logged-in user
- administrator privileges
- FileVault state where detectable
- SIP state where detectable
- available developer tools
- Xcode Command Line Tools
- Xcode version, if installed
- Homebrew
- Homebrew architecture/prefix
- `mas`
- iCloud container availability as a sign-in hint
- App Store application availability
- configuration profile / device-management hints

Do not hard-code assumptions about current macOS versions. Extend the capability-detection layer as providers need more precise evidence.

## Hardware Applicability

For each setting, define applicability:

- universal
- apple-silicon-only
- intel-only
- laptop-only
- desktop-only
- external-display-dependent
- external-input-device-dependent
- user-specific
- machine-specific
- managed-device-only

When applying a snapshot, Mimicry must evaluate applicability and skip incompatible settings with an explanation.

Example:

```text
Reference:
    MacBook Pro
    Trackpad enabled

Destination:
    Mac mini
    No built-in trackpad

Result:
    Skip trackpad-specific setting
    Explain why
    Continue deployment
```

## Managed Macs

Detect whether the Mac is managed through MDM or has installed configuration profiles.

Mimicry must:

- detect installed configuration profiles
- identify whether the Mac appears to be managed
- clearly distinguish managed settings from user-controlled settings
- avoid attempting to override MDM-enforced configuration
- report settings that cannot be changed because they are managed

Do not attempt to remove or bypass MDM.
