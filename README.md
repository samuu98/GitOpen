# GitOpen

Cross-platform open-source desktop git client built on Flutter.
Inspired by Fork. Targets Windows and Linux.

> **Fork maintained by [zN3utr4l](https://github.com/zN3utr4l).** Based on the
> original [GitOpen](https://github.com/samuu98/GitOpen) by s.porta (MIT).

> **Status:** Slice 2 (write operations) complete. See
> `docs/superpowers/specs/` and `docs/superpowers/plans/` for roadmap.

## Build and run

Prerequisites:
- Flutter SDK (stable channel)
- `git` CLI on `PATH` (Git for Windows on Windows; `apt install git` on Ubuntu)
- Windows: Visual Studio 2022 with "Desktop development with C++" workload
- Linux: `sudo apt install clang cmake ninja-build libgtk-3-dev`

```powershell
# Windows
flutter pub get
flutter run -d windows
```

```bash
# Linux
flutter pub get
flutter run -d linux
```

## Tests

```bash
flutter test
```

## Slice 1 — Read-only viewer

- Commit graph with lane painting (multi-branch colour-coded lanes)
- Branch and tag ref pills; HEAD marker
- Bottom panel: commit details, unified diff view, file tree
- Sidebar: branch/tag/remote/stash tree
- Multi-repo tabs with persistence across restarts
- Chromeless window (bitsdojo_window) with Fork-inspired dark palette

## Slice 2 — Write operations

- **Commit**: file-level and hunk-level staging; amend; sign-off; Ctrl+Enter shortcut
- **Branch CRUD**: create, switch, rename, delete
- **Fetch / Pull / Push**: streaming progress via `git --progress`, toast notifications
- **Stash**: save with message, apply, pop, list
- **Merge with conflict detection**: detects in-progress merge/cherry-pick state, shows conflict resolution panel with "Continue" / "Abort"
- **Cherry-pick**: pick any commit from the graph onto HEAD
- **Clone**: public and private repos via Clone dialog
- **GitHub OAuth Device Flow**: browser-based token acquisition stored via `flutter_secure_storage`
- **Keyboard shortcuts**: Ctrl+Enter (commit), F5 (fetch)
- **Activity panel**: running-operation toasts with progress fraction

## Slice 3 — Distribution & Polish

- **Settings UI**: full settings page with General, Auth, Keybindings, GitHub, Updates, and About tabs
- **Light/Dark themes**: switchable in Settings → General; all panels and panels respect the selected palette
- **Custom keybindings**: rebind 6 actions (Commit, Fetch, Push, Pull, Cherry-pick, Stash) in Settings → Keybindings
- **Revert**: right-click any commit in the graph → "Revert this commit"; conflict flow reuses the Conflict Resolution panel
- **Status bar**: persistent bar showing current branch name, ahead/behind counts, and running-ops counter
- **MSIX packaging** (Windows): `dart run msix:create` — produces a signed-layout `.msix` installer
  > **Note:** The MSIX is not code-signed. Windows SmartScreen will warn on first install — click **More info → Run anyway** to proceed.
- **AppImage build** (Linux): run `bash scripts/build-appimage.sh`; outputs `GitOpen-x86_64.AppImage`
- **Auto-update checker**: on startup (and via Settings → Updates → "Check now") queries GitHub Releases for a newer `v*.*.*` tag and prompts the user to download

## License

MIT
