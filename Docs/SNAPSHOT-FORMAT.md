# Snapshot Format

The snapshot format is versioned, portable, inspectable, and human-readable.

Initial format: a macOS package bundle with the extension `.mimicry`.

```text
my-mac.mimicry/
    manifest.json
    snapshot.json
    logs/
    browser/
    applications/
    encrypted/
    checksums.json
    README.md
```

## Minimum Metadata

- schema version
- Mimicry version
- created timestamp
- source macOS version
- source architecture
- hardware model
- provider versions
- compatibility notes
- excluded sensitive-data report
- checksums

The snapshot must not contain passwords, tokens, cookies, private keys, browser session data, Keychain contents, or cloud credentials by default.

## Current Sections

Mimicry currently writes these initial sections into `snapshot.json`:

- `environment`: macOS, architecture, hardware model, hostname, username, admin status, tool availability, and service states. This section is provenance and comparison metadata; apply planning skips it rather than applying machine- or user-specific identity to another Mac.
- `homebrew`: Homebrew availability, prefix, architecture, version, taps, formulae, and casks.
- `app-store`: `mas` availability and App Store application inventory when `mas list` completes successfully.
- `finder`: stable Finder preferences captured with `defaults read`, including absent values where individual defaults are not set.
- `terminal`: shell metadata and reviewed shell configuration file metadata, with secret-like files marked redacted and without storing shell file contents.
- `icloud`: local iCloud status metadata, required-user-action state, and an explicit marker that authentication state is excluded.

These sections are read-only inventory. They do not perform installs, upgrades, sign-ins, preference writes, identity changes, or other system mutation.

## Export Container Decision

Begin with a package bundle rather than a plain directory or compressed archive.

Package bundle benefits:

- Appears as a single file-like artifact in Finder.
- Can be opened by Mimicry through a custom document type.
- Keeps internal JSON, logs, browser files, encrypted sections, and checksums inspectable during development.
- Avoids compression/extraction friction during early schema migration work.
- Leaves room to mark it as a document package in the app's exported Uniform Type Identifier.

Package bundle tradeoffs:

- Not as convenient for transfer through tools that expect a single byte stream.
- Can be partially copied if moved by low-level tools incorrectly.
- Needs checksums so Mimicry can detect missing or modified internal files.

Plain directory tradeoffs:

- Easiest to inspect and generate.
- Least polished for users.
- Too easy to accidentally separate internal files from the snapshot.

Compressed archive tradeoffs:

- Best for transfer, sharing, and immutable export.
- Less convenient for inspection, diffing, partial repair, and migration.
- Better as a later `mimicry export --archive` option than the primary working format.

Decision: `.mimicry` starts as an inspectable package bundle. Add compressed export/import once the schema and checksum model have stabilized.

## Encryption Decision

Encrypted optional snapshot sections are part of the MVP.

MVP encryption should be explicit, opt-in, and passphrase-based. The normal snapshot remains secret-free. If a provider supports a sensitive-but-useful setting later, Mimicry can place that section under `encrypted/` with clear user approval, strong warnings, checksums, and a separate restore path. No provider may silently place secrets in either the normal snapshot or encrypted sections.

For MVP, do not store the encryption passphrase in Keychain. The user should type the passphrase when creating or restoring encrypted sections. Keychain convenience can be considered later after the encrypted section model has tests and real-world validation.
