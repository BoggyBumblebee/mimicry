# Codex Build Prompt: Mimicry — Native macOS Deployment Replication Tool

## Role

You are an expert macOS software engineer, Swift/SwiftUI developer, systems administrator, and macOS automation engineer.

Design and build a production-quality native macOS application called **Mimicry**.

Mimicry is intended for users who maintain multiple Macs and want newly installed or freshly reset Macs to behave as consistently as possible with a trusted "reference" Mac.

The core concept is:

> **Snapshot a known-good Mac, then apply that snapshot to another Mac in a safe, deterministic, inspectable and repeatable way.**

Mimicry is intended to replace/rethink an existing Ansible-based workflow:

https://github.com/geerlingguy/mac-dev-playbook

The existing project has been useful for many years but has become increasingly unreliable as macOS versions have changed. Mimicry should therefore be designed specifically around modern macOS rather than simply porting the existing Ansible implementation.

---

## 1. Primary objectives

Mimicry must support two fundamental operations:

### A. Snapshot

Inspect the current Mac and create a **Mimicry Snapshot** describing the configuration that should be reproduced elsewhere.

```text
Reference Mac
    |
    +-- Applications
    |     +-- App Store applications
    |     +-- Homebrew formulae
    |     +-- Homebrew casks
    |
    +-- macOS configuration
    +-- User configuration
    +-- iCloud configuration
    +-- Finder configuration
    +-- Terminal configuration
    +-- Browser configuration
    |     +-- Safari
    |     +-- Chrome
    |     +-- Firefox
    |
    +-- Application-specific configuration
    +-- Hardware / environment information
    +-- Compatibility metadata
```

### B. Apply

Take a Mimicry Snapshot and apply it to a fresh or existing Mac.

The destination Mac should become as close as reasonably possible to the reference Mac without copying inappropriate machine-specific state, credentials, secrets, or incompatible settings.

---

## 2. Important architectural principle

**Do NOT implement Mimicry as a generic "copy everything in ~/Library" application.**

Modern macOS stores configuration using multiple mechanisms.

The implementation must classify configuration into appropriate mechanisms such as:

1. macOS command-line interfaces
2. `defaults` / CFPreferences
3. configuration profiles where appropriate
4. application configuration files
5. application containers
6. browser-specific export/import mechanisms
7. Homebrew manifests
8. Mac App Store application identifiers
9. Keychain references where appropriate
10. iCloud configuration/state
11. user shell configuration
12. macOS system configuration
13. hardware-dependent settings

Prefer documented/public macOS mechanisms wherever possible.

Where a documented mechanism does not exist, use the most stable available mechanism and isolate that implementation behind a versioned provider/adapter.

Do not depend unnecessarily on undocumented private APIs.

---

## 3. Native macOS implementation

Build Mimicry as a **native macOS application**.

Preferred technology:

- Swift
- SwiftUI
- Apple's native frameworks
- macOS native process execution where shell commands are required
- Swift Package Manager for dependencies

Avoid Electron, Python GUI frameworks, Java, Node.js or cross-platform UI frameworks unless there is a compelling technical reason.

The application should feel like a first-class macOS application.

Target modern Apple Silicon Macs first, while retaining support for Intel Macs where practical.

The code must be structured so that macOS-version-specific behavior can be isolated rather than scattered throughout the application.

---

## 4. Supported macOS versions

At startup, detect:

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
- iCloud login state
- App Store authentication state
- configuration profiles / device management state

Do not hard-code assumptions about current macOS versions.

Implement a capability-detection layer.

```swift
struct MacCapabilities {
    let macOSVersion: OperatingSystemVersion
    let architecture: Architecture
    let isAppleSilicon: Bool
    let hasHomebrew: Bool
    let hasMAS: Bool
    let hasCommandLineTools: Bool
    let isAppStoreAuthenticated: Bool
    let isICloudSignedIn: Bool
    let isManaged: Bool
}
```

---

## 5. Snapshot format

Create a formal, versioned snapshot format.

Prefer a human-readable format such as JSON.

```json
{
  "schemaVersion": 1,
  "mimicryVersion": "1.0.0",
  "createdAt": "2026-08-11T14:00:00Z",
  "source": {
    "macOSVersion": "26.x",
    "architecture": "arm64",
    "hardware": "MacBookPro..."
  },
  "applications": {
    "appStore": [],
    "homebrewFormulae": [],
    "homebrewCasks": []
  },
  "system": {},
  "icloud": {},
  "finder": {},
  "terminal": {},
  "browsers": {}
}
```

The schema must be explicitly versioned so that:

- old snapshots can be read
- newer versions can migrate old snapshots
- unsupported settings can be identified
- snapshots can be validated before application

The snapshot should be portable between Macs.

Do not include passwords, private keys, authentication tokens, cookies, session data, or other secrets in the normal snapshot.

---

## 6. Applications

### 6.1 Mac App Store

Mimicry must discover applications installed from the Mac App Store.

Use `mas` where appropriate.

The snapshot should record at minimum:

- Apple/Bundle/Application identifier
- Name
- Installed version
- Source = AppStore

Prefer application identifiers over application names for restoration.

```json
{
  "source": "appStore",
  "bundleIdentifier": "com.example.application",
  "name": "Example",
  "installedVersion": "1.2.3"
}
```

Do not assume the application is still available in the App Store.

During Apply:

1. Detect whether `mas` exists.
2. If not, offer to install it through Homebrew.
3. Verify App Store authentication.
4. Verify the application is available.
5. Install it.
6. Record success/failure.
7. Continue rather than aborting the entire deployment.

Never store an Apple Account password.

Never attempt to automate authentication by scraping or storing credentials.

---

## 7. Homebrew

Mimicry must support Homebrew.

Detect:

- whether Homebrew exists
- architecture
- Homebrew prefix
- installed formulae
- installed casks
- taps
- optionally pinned packages where relevant

Generate a Homebrew manifest similar to:

```json
{
  "formulae": [],
  "casks": [],
  "taps": []
}
```

Use appropriate Homebrew commands rather than inspecting the Cellar directly.

Distinguish clearly between:

- formulae
- casks
- taps

Do not blindly copy Homebrew's installation directories.

During Apply:

1. Detect whether Homebrew exists.
2. Detect Apple Silicon vs Intel.
3. Install Homebrew if necessary using the current official Homebrew installation mechanism.
4. Ensure the correct Homebrew environment is available to the current shell.
5. Restore taps.
6. Install formulae.
7. Install casks.
8. Report packages that no longer exist.
9. Continue on individual failures.

Do not permanently embed a copied Homebrew installer script.

---

## 8. Xcode Command Line Tools

Mimicry must detect whether Command Line Tools are installed.

If Homebrew is required but developer tools are missing, explain the prerequisite and provide the appropriate macOS installation workflow.

Do not attempt to bypass Apple's confirmation or licensing mechanisms.

Detect:

```text
xcode-select
xcrun
clang
git
```

Support both:

- Command Line Tools only
- full Xcode installation

Do not assume that installing Xcode automatically means every required command-line component is configured correctly.

---

## 9. System configuration

The application should capture **reproducible macOS configuration**, not an indiscriminate dump of every preference file.

Build a framework of configuration providers.

```text
SystemConfigurationProvider
FinderConfigurationProvider
DockConfigurationProvider
KeyboardConfigurationProvider
TrackpadConfigurationProvider
MouseConfigurationProvider
DesktopConfigurationProvider
MissionControlConfigurationProvider
AppearanceConfigurationProvider
AccessibilityConfigurationProvider
PrivacyConfigurationProvider
NotificationConfigurationProvider
LoginConfigurationProvider
NetworkConfigurationProvider
PowerConfigurationProvider
SecurityConfigurationProvider
```

Not every provider needs to be implemented in version 1, but the architecture must allow providers to be added independently.

Each provider should expose something conceptually like:

```swift
protocol ConfigurationProvider {
    var identifier: String { get }
    var displayName: String { get }

    func detect() async throws -> ConfigurationState
    func snapshot() async throws -> SnapshotSection
    func validate(snapshot: SnapshotSection) async throws -> ValidationResult
    func apply(snapshot: SnapshotSection) async throws -> ApplyResult
}
```

---

## 10. Hardware-specific configuration

Some settings make sense on laptops, desktops, external keyboards, external displays, trackpads, mice, Apple Silicon Macs, or Intel Macs. Others do not.

Every snapshot must contain source hardware information.

For each setting, define applicability:

```text
universal
apple-silicon-only
intel-only
laptop-only
desktop-only
external-display-dependent
external-input-device-dependent
user-specific
machine-specific
managed-device-only
```

When applying a snapshot, Mimicry must evaluate applicability.

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

Never make an obviously incompatible setting fail the entire restore.

---

## 11. Configuration profiles and managed Macs

Detect whether the Mac is managed through MDM or has installed configuration profiles.

Mimicry must:

- detect installed configuration profiles
- identify whether the Mac appears to be managed
- clearly distinguish managed settings from user-controlled settings
- avoid attempting to override MDM-enforced configuration
- report settings that cannot be changed because they are managed

Do not attempt to remove or bypass MDM.

For managed settings, report:

```text
Managed by organization
Not modified by Mimicry
```

---

## 12. iCloud

Mimicry must explicitly handle iCloud as a special case.

Do NOT attempt to clone an Apple Account.

Do NOT store Apple Account credentials.

Do NOT attempt to copy private iCloud authentication state.

Instead, snapshot the desired **iCloud service configuration** and use that to guide configuration of the destination Mac.

Examples include:

- iCloud Drive
- Desktop & Documents
- Photos
- Safari
- Contacts
- Calendars
- Reminders
- Notes
- Passwords / Keychain
- Find My
- other available iCloud services

The snapshot should distinguish:

```text
desired state
authentication required
automatically synced
manual user action required
unsupported
```

If the user is not signed into iCloud, pause or skip the relevant stage and clearly request the required user action.

Do not fake or bypass authentication.

---

## 13. Finder

Finder is a first-class configuration target.

Capture reproducible Finder preferences such as:

- sidebar configuration
- show/hide extensions
- show/hide hidden files
- default folder view
- icon/list/column/gallery preferences where feasible
- path bar
- status bar
- toolbar configuration where feasible
- desktop behavior
- tag configuration where feasible
- new Finder window behavior
- filename extension preferences
- other stable Finder preferences

Do not simply copy all Finder preference files.

Use provider-specific extraction and restoration.

Restart affected processes only when required.

---

## 14. Terminal

Capture the user's terminal environment.

Include, where present:

- shell
- default shell configuration
- `.zshrc`
- `.zprofile`
- `.bash_profile`
- `.bashrc`
- `.profile`
- shell aliases
- shell functions
- PATH customization
- Homebrew shell integration
- relevant shell environment configuration

Do not copy secrets.

Before including a file in a snapshot, detect potentially sensitive content.

Potential secret categories include:

- API keys
- tokens
- passwords
- private keys
- credentials
- cloud access keys
- SSH private keys

Classify configuration as:

```text
safe configuration
potentially sensitive
excluded
user must review
```

---

## 15. Browsers

Support:

- Safari
- Google Chrome
- Firefox

The first version must at minimum support:

- browser installed
- browser version
- bookmarks
- bookmark structure/folders
- browser-specific configuration that can be safely reproduced

Design browser integrations independently.

---

## 16. Safari

Implement a dedicated `SafariProvider`.

It should:

- detect Safari
- determine whether iCloud Safari synchronization is enabled
- snapshot bookmarks where safely possible
- restore bookmarks where safely possible
- preserve bookmark folders and hierarchy
- report when iCloud is expected to supply the data instead

Avoid conflicting restoration when iCloud Safari synchronization is active.

Conceptually:

```text
iCloud Safari enabled?
    YES -> prefer iCloud synchronization
    NO  -> restore explicit bookmark data
```

---

## 17. Google Chrome

Implement a dedicated Chrome provider.

At minimum:

- detect installation
- detect profile(s)
- capture bookmarks
- restore bookmarks
- capture safe user preferences where practical

Do not blindly copy Chrome profile databases.

Do not copy:

- cookies
- passwords
- authentication tokens
- session cookies
- encryption keys
- other credentials

Handle multiple Chrome profiles explicitly.

---

## 18. Firefox

Implement a dedicated Firefox provider.

At minimum:

- detect installation
- detect profiles
- capture bookmarks
- restore bookmarks
- capture safe configuration where practical

Do not blindly copy sensitive profile databases.

Handle multiple Firefox profiles explicitly.

---

## 19. Other applications

Mimicry should support application-specific configuration through a plugin/provider architecture.

```text
ApplicationProvider
    bundleIdentifier
    displayName
    snapshot()
    validate()
    apply()
```

The system should allow future providers such as:

- Visual Studio Code
- JetBrains products
- iTerm2
- Slack
- Docker
- 1Password
- Git clients
- Terminal applications
- VPN clients
- Developer tools

Each provider must explicitly define:

```text
safe configuration
unsafe configuration
machine-specific configuration
credential-bearing configuration
unsupported configuration
```

---

## 20. Application discovery

Discover applications from multiple sources:

```text
/Applications
~/Applications
Homebrew Casks
Mac App Store
system applications
```

Do not treat every `.app` found on disk as something to reinstall.

System applications supplied by Apple should normally be represented as:

```text
provided by macOS
```

For third-party applications not installed through Homebrew or the App Store, record:

```text
application present
source unknown
restoration unavailable
```

Optionally allow the user to manually define an installation source.

---

## 21. Snapshot inspection

The user must be able to inspect a snapshot before applying it.

Example UI:

```text
Mimicry Snapshot
────────────────────────────

Applications              84
System Settings           32
Finder                     8
Terminal                   6
Browser Configuration     17
Application Settings      29
iCloud                     9

Warnings                   4
Hardware-specific          6
Secrets excluded           3

[Review] [Export] [Apply]
```

Users must be able to drill into sections.

---

## 22. Diff capability

Add a **Compare** mode.

Given a Reference Snapshot and Current Mac, show:

```text
MATCHED
    Safari installed

MISSING
    Visual Studio Code
    Docker

DIFFERENT
    Finder hidden files = true
    Current Mac = false

INCOMPATIBLE
    Trackpad setting
    Destination has no trackpad

MANAGED
    Firewall setting controlled by MDM

UNSUPPORTED
    Application XYZ setting
```

---

## 23. Dry run

Support:

```bash
mimicry apply snapshot.json --dry-run
```

A dry run must produce a complete proposed action list without changing the Mac.

```text
INSTALL
    Homebrew
    mas
    Firefox

CONFIGURE
    Finder
    Terminal
    Dock

SKIP
    Trackpad settings - destination is desktop

REQUIRES USER ACTION
    Sign in to App Store
    Sign in to iCloud

BLOCKED
    Managed system setting
```

---

## 24. Idempotency

Applying the same snapshot repeatedly should be safe.

It must not:

- duplicate bookmarks
- duplicate applications
- corrupt configuration
- continually toggle settings
- repeatedly overwrite files unnecessarily

Every operation should be idempotent wherever possible.

---

## 25. Transaction / rollback philosophy

Before modifying existing configuration:

- create backups of affected files/settings where practical
- record changes
- maintain an operation log

Provide an "Undo recent Mimicry changes" capability where feasible.

Do not promise complete rollback where macOS does not expose a reversible mechanism.

Explicitly document rollback boundaries.

---

## 26. Secrets and privacy

Security is a first-class requirement.

By default, exclude:

- passwords
- Keychain contents
- private keys
- browser cookies
- browser passwords
- authentication tokens
- OAuth credentials
- cloud credentials
- application session tokens
- SSH private keys
- API tokens
- certificates containing private keys

Provide a report of excluded sensitive data.

Do not upload snapshots anywhere by default.

Snapshots should remain local unless the user explicitly exports or transfers them.

---

## 27. Logging

Provide detailed structured logs.

Each action should contain:

```text
timestamp
provider
operation
result
reason
error
```

Provide both human-readable and machine-readable logs.

---

## 28. Command-line interface

Although the primary experience should be a native GUI, also implement a CLI.

```bash
mimicry snapshot
mimicry snapshot --output ~/Desktop/my-mac.mimicry

mimicry inspect ~/Desktop/my-mac.mimicry

mimicry validate ~/Desktop/my-mac.mimicry

mimicry apply ~/Desktop/my-mac.mimicry

mimicry apply ~/Desktop/my-mac.mimicry --dry-run

mimicry diff ~/Desktop/my-mac.mimicry

mimicry doctor
```

The CLI should be suitable for scripting.

Use a single underlying implementation shared by GUI and CLI.

---

## 29. Doctor / diagnostics mode

Implement:

```bash
mimicry doctor
```

It should inspect the current Mac and report readiness.

```text
Mimicry Doctor
==============

macOS              PASS
Architecture       PASS    arm64
Admin privileges   PASS
Xcode CLT          PASS
Homebrew           PASS
mas                PASS
App Store login    WARN    Authentication required
iCloud             WARN    Not signed in
MDM                INFO    Device managed
Disk space         PASS

Ready for:
    Homebrew restore
    App Store restore

Requires user action:
    App Store authentication
    iCloud authentication
```

---

## 30. UI design

The UI should be simple and Mac-like.

Primary navigation:

```text
Snapshot
Apply
Compare
History
Settings
Diagnostics
```

Home screen:

```text
Mimicry

This Mac
MacBook Pro — macOS

[ Create Snapshot ]

Reference Snapshot
My Mac Configuration

[ Inspect ]
[ Compare ]
[ Apply ]
```

Show clear progress during Apply.

---

## 31. User approval and elevation

Some operations will require:

- administrator privileges
- sudo
- user authentication
- App Store authentication
- iCloud authentication
- privacy permissions

Do not silently request excessive privileges.

Request elevation only when needed.

Explain why elevated privileges are necessary.

Never collect or store the user's password.

---

## 32. Error handling

Classify outcomes:

```text
FATAL
BLOCKED
WARNING
SKIPPED
UNSUPPORTED
SUCCESS
```

A single failed package or preference should not normally terminate the entire deployment.

At completion, present a summary of successful, skipped, warning, failed, and user-action-required operations.

---

## 33. Version compatibility

The reference Mac may run a different macOS version from the destination.

Providers must declare compatibility.

For settings, capture where practical:

```text
introduced
last-known-compatible
deprecated
hardware requirements
```

When a setting cannot safely be applied, skip it and explain why.

Do not blindly execute old configuration against a new operating system.

---

## 34. Configuration provider architecture

Suggested structure:

```text
Mimicry/
    App/
    Core/
        Snapshot/
        Apply/
        Diff/
        Validation/
        Logging/
        Security/
    Providers/
        System/
        Homebrew/
        AppStore/
        Finder/
        Terminal/
        iCloud/
        Safari/
        Chrome/
        Firefox/
        Applications/
    CLI/
    UI/
    Models/
    Tests/
```

Each provider should be independently testable.

---

## 35. Testing strategy

Build automated tests from the beginning.

### Snapshot tests

- snapshot schema
- serialization
- deserialization
- migration
- sensitive-data filtering

### Provider tests

- Homebrew discovery
- App Store discovery
- Finder configuration
- browser bookmark parsing
- Terminal configuration

### Compatibility tests

- Apple Silicon vs Intel
- laptop vs desktop
- differing macOS versions

### Apply tests

- idempotency
- dry run
- failure handling
- partial failure
- rollback behavior

### Security tests

Verify that snapshots cannot accidentally contain:

- passwords
- private keys
- tokens
- browser credentials
- cookies

---

## 36. External dependencies

Minimise dependencies.

Where an external command is essential, create an abstraction such as:

```swift
protocol CommandRunner {
    func run(
        executable: URL,
        arguments: [String],
        environment: [String:String]?
    ) async throws -> CommandResult
}
```

Never scatter raw shell commands throughout the application.

---

## 37. Homebrew and MAS should be optional providers

Mimicry should not fundamentally depend on Homebrew.

The system should support:

```text
App Store Provider
Homebrew Provider
Native macOS Provider
Application Provider
```

Homebrew and `mas` can be bootstrapping mechanisms, but the core snapshot engine should remain independent of them.

---

## 38. Snapshot portability

A snapshot should be exportable as:

```text
my-mac.mimicry
```

Internally this may be a directory/archive containing:

```text
manifest.json
snapshot.json
browser/
applications/
configurations/
checksums.json
README.md
```

Use checksums to detect corruption.

Consider optional encryption for user-approved sensitive configuration.

---

## 39. Future capabilities

Design the architecture so future versions can add:

- additional browsers
- more application providers
- login items
- LaunchAgents
- SSH configuration
- Git configuration
- Docker configuration
- development environments
- VS Code extensions
- package managers other than Homebrew
- network configuration
- printers
- VPN configuration
- external displays
- keyboard shortcuts
- accessibility settings
- menu bar applications
- Dock layouts
- Spaces / Mission Control
- MDM integration
- remote deployment
- snapshot signing
- snapshot repositories
- organization-wide profiles

Do not implement all of these in version 1 unless necessary to establish the architecture.

---

## 40. MVP

The first implementation should prioritize an end-to-end workflow.

### MVP Snapshot

Implement:

1. macOS environment detection
2. Homebrew formula discovery
3. Homebrew cask discovery
4. Homebrew taps
5. Mac App Store application discovery using `mas`
6. basic Finder configuration
7. basic Terminal configuration
8. iCloud state detection
9. Safari bookmark/configuration handling
10. Chrome bookmarks
11. Firefox bookmarks
12. snapshot generation
13. snapshot inspection
14. validation
15. dry run
16. apply
17. structured logging
18. CLI
19. native SwiftUI UI

Then expand provider coverage incrementally.

---

## 41. Important implementation rule

Do not claim that Mimicry can reproduce "all macOS settings" until every setting has an explicit implementation and test.

The application must always tell the user:

- what was captured
- what can be restored
- what was excluded
- what is hardware-specific
- what is macOS-version-specific
- what requires authentication
- what is managed by MDM
- what is unsupported

---

## 42. Documentation

Produce comprehensive documentation alongside the implementation.

At minimum:

```text
README.md
ARCHITECTURE.md
SNAPSHOT-FORMAT.md
SECURITY.md
PROVIDERS.md
DEVELOPMENT.md
TESTING.md
COMPATIBILITY.md
```

Document assumptions, external commands, setting providers, and limitations.

---

## 43. Development process

Do not attempt to implement the entire application in one giant change.

### Phase 1

- project scaffold
- architecture
- snapshot model
- CLI
- UI shell
- logging

### Phase 2

- environment detection
- Homebrew provider
- App Store provider
- diagnostics

### Phase 3

- Finder
- Terminal
- iCloud

### Phase 4

- Safari
- Chrome
- Firefox

### Phase 5

- diff
- dry run
- apply
- rollback support

### Phase 6

- additional application providers
- compatibility improvements
- hardening
- documentation

After each phase:

1. compile
2. run tests
3. run static checks
4. manually test on a real macOS machine where applicable
5. document limitations
6. do not proceed with known architectural problems

---

## 44. Codex operating instructions

Before writing significant code:

1. Inspect the existing `geerlingguy/mac-dev-playbook` repository and understand what it currently attempts to configure.
2. Identify which parts should be preserved conceptually and which parts should be discarded.
3. Inspect current macOS APIs and command-line mechanisms relevant to the requirements.
4. Verify assumptions against current Apple, Homebrew and MAS documentation.
5. Produce a concise architecture proposal.
6. Identify the MVP provider list.
7. Identify known limitations and risky areas.
8. Then begin implementation.

Do not blindly port the old Ansible playbook.

Do not use obsolete macOS techniques simply because they worked on older releases.

Where there are multiple implementation approaches, prefer:

1. documented Apple API
2. documented Apple command-line mechanism
3. supported configuration profile
4. stable application-specific interface
5. well-understood configuration file
6. `defaults` / CFPreferences
7. legacy/undocumented mechanism only as a last resort

Every provider should document why its selected mechanism is appropriate.

---

## 45. Definition of success

Mimicry is successful when I can do this on my trusted Mac:

```bash
mimicry snapshot --output ~/Desktop/primary-mac.mimicry
```

Then on a newly installed Mac:

```bash
mimicry doctor
mimicry apply ~/Desktop/primary-mac.mimicry --dry-run
mimicry apply ~/Desktop/primary-mac.mimicry
```

After completion, the new Mac should have:

- the same desired Homebrew packages
- the same desired Mac App Store applications
- the same supported Finder configuration
- the same supported Terminal configuration
- the same supported macOS configuration
- the same desired iCloud configuration
- the same browser bookmarks
- the same supported browser configuration
- the same supported application configuration

while avoiding:

- copied passwords
- copied private keys
- copied session tokens
- copied cookies
- copied authentication state
- incompatible hardware settings
- MDM violations
- destructive overwrites
- macOS-version incompatibilities

The user should be able to understand exactly what Mimicry changed and why.

---

## Final principle

Mimicry is not a backup utility.

It is not a disk cloning utility.

It is not a credential migration tool.

It is a **configuration declaration and reconciliation system for macOS**.

The desired end state is:

> **This snapshot describes how I want my Mac configured. Make this Mac conform to that configuration, as far as safely and technically possible.**

Build the system around that principle.
