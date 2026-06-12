# Portable Windows zip distribution — design

**Date:** 2026-06-12
**Status:** Approved

## Problem

The release pipeline ships Windows builds only as an unsigned Inno Setup
installer (`GitOpen-Setup-x.y.z.exe`). Windows Defender's heuristics flag
unsigned installers as malware (typical false positive: Wacatac), blocking
installation even for administrators. Code signing is the long-term fix but
needs a certificate; until then users need a way to run GitOpen that does not
trip the anti-installer heuristic.

## Decision

Publish a portable zip **alongside** the installer (not replacing it).
"Portable" means *no installer required* only: app settings stay in their
standard per-user location (`%APPDATA%`). No Dart code changes.

## Design

- `release.yml`, job `windows-installer`: after the Flutter Windows build,
  a new step stages `build\windows\x64\runner\Release\*` under a root
  `GitOpen\` folder and compresses it with `Compress-Archive` into
  `build/installer/GitOpen-Portable-{version}.zip`. The root folder ensures
  extraction does not scatter loose files.
- The `upload-artifact` and `action-gh-release` steps publish both
  `GitOpen-Setup-*.exe` and `GitOpen-Portable-*.zip`.
- README gains a Download section describing both Windows artifacts and the
  `.deb`, with a note that the portable exe is still unsigned, so SmartScreen
  may ask for confirmation on first launch ("More info → Run anyway") — but
  the zip avoids Defender's installer quarantine.

## Alternatives considered

- **Separate `windows-portable` job** — rebuilds the same binaries, ~5–8 min
  extra CI for identical output. Rejected.
- **7-Zip instead of Compress-Archive** — marginally better compression at
  the cost of an extra dependency. Rejected (YAGNI).
- **True portable mode** (settings next to the exe via marker file) — needs
  Dart changes and tests; out of scope, can be a future slice item.

## Testing

Manual `workflow_dispatch` run of `release.yml`; download the artifact,
extract, verify `GitOpen\gitopen.exe` launches.
