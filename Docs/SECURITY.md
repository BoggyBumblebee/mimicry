# Security

Security is a first-class requirement.

Mimicry must always tell the user:

- what was captured
- what can be restored
- what was excluded
- what is hardware-specific
- what is macOS-version-specific
- what requires authentication
- what is managed by MDM
- what is unsupported
- what changed
- why it changed

## Never Capture Silently

Mimicry must never:

- store Apple Account credentials
- store passwords
- copy Keychain contents
- copy private keys
- copy browser cookies or session tokens
- bypass macOS authentication
- bypass MDM
- claim complete macOS reproduction without explicit provider support and tests

## Secrets Policy

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

Snapshots should remain local unless the user explicitly exports or transfers them.

## App Sandbox Decision

App sandbox is disabled for the MVP. Mimicry needs broad local inspection and user-approved configuration access that does not fit the Mac App Store sandbox model.

This does not loosen product behavior. Providers still need explicit scope, validation, and user-facing explanations.

## Privileged Helper Policy

A privileged helper means a separate helper executable, usually a LaunchDaemon, that runs with elevated privileges and performs operations the normal app or CLI cannot safely perform as the current user.

Mimicry should not start with a persistent privileged helper. The MVP should prefer:

- user-context actions whenever possible
- documented Apple APIs
- explicit user approval
- clear manual instructions where macOS requires a human step
- one-shot authorization or `sudo`-style CLI workflows only when a provider genuinely requires it

Reasons to avoid a helper in the MVP:

- It increases signing, entitlement, install, update, and uninstall complexity.
- It expands the security review surface.
- It can make users nervous because it adds a root-capable background component.
- Many MVP actions, including Homebrew, App Store detection, Finder preferences, Terminal files, bookmarks, dry-run planning, and snapshot inspection, do not need a root daemon.

When a privileged helper becomes necessary, it should use the modern Service Management model with helper resources inside the app bundle, registered through `SMAppService`, and controlled through System Settings approval. The helper must expose a narrow XPC API, never accept raw shell strings, log every privileged action, and be optional unless the selected provider requires it.

Candidate post-MVP helper use cases:

- system-wide settings that require root
- installing or managing LaunchDaemons
- managed backup/rollback of protected files
- system-level configuration profile workflows where appropriate
- carefully scoped operations that cannot be expressed safely through user-context commands
