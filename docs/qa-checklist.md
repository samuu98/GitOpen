# Manual QA Checklist (Slice 1 — read-only viewer)

Run on both Windows and Ubuntu before each release.

## Smoke
- [ ] App launches, main window appears
- [ ] No errors in `%APPDATA%/GitOpen/logs/` (Win) or `~/.config/GitOpen/logs/` (Linux)

## Open repository
- [ ] "+" tab opens folder picker
- [ ] Selecting a folder containing `.git` adds a tab; sidebar populates
- [ ] Selecting a folder without `.git` shows an error toast (or graceful empty)

## Multiple repos
- [ ] Open 3 repos; tabs visible; clicking each switches the panel
- [ ] Close a tab via × removes it from the bar

## Commit graph
- [ ] Repo with linear history shows single lane
- [ ] Repo with branches shows multiple coloured lanes
- [ ] Scroll through 5000+ commits is fluid
- [ ] Branch and tag pills appear on the correct rows
- [ ] HEAD → marker on current branch pill

## Bottom panel
- [ ] Click a commit → Commit tab shows author, sha, full message
- [ ] Changes tab shows diff with +/- lines and hunk headers
- [ ] Binary files show "Binary file (no preview)"
- [ ] File Tree tab lists root entries; folders sort first

## Persistence
- [ ] Open 2 repos, close app, reopen — both repos reopen automatically
- [ ] Move a repo folder, reopen app — the missing repo is silently dropped (logged)

## Resilience
- [ ] Open a very large repo (10k+ commits) — initial load < 5 s
- [ ] Open an empty repo (no commits) — graph panel shows "No commits"

---

# Manual QA Checklist (Slice 2 — Write operations)

Run on Windows before the `slice-2-write-ops` release tag.

## Clone
- [ ] Clone a public GitHub repo via Clone dialog (HTTPS, no auth)

## Commit workflow
- [ ] Open Working Copy → stage a hunk → type a message → commit → see new commit in graph
- [ ] Open Working Copy → tick "Amend last commit" → update message → commit

## Branch operations
- [ ] Create a new branch from HEAD → switch to it → make a commit → graph shows new branch tip

## Sync operations
- [ ] Fetch / Pull / Push to a remote (use a personal test repo) — progress toast appears and dismisses

## Stash
- [ ] Stash changes (with a message) → verify working copy is clean → Pop → verify changes restored

## Conflict resolution
- [ ] Trigger a merge conflict → conflict resolution panel appears → open conflicting file in VS Code → resolve → Continue → merge commit visible in graph

## Cherry-pick
- [ ] Cherry-pick a commit from another branch → new commit appears on current branch

## Reset
- [ ] Right-click a commit row → Reset (hard) → confirmation dialog → graph rewinds

## Tags
- [ ] Tag a commit via context menu → tag pill appears in graph → delete the tag → pill disappears

## Keyboard shortcuts
- [ ] With Working Copy open, Ctrl+Enter triggers commit (when message is non-empty)
- [ ] F5 triggers fetch for the active repo (toast appears)

---

# Manual QA Checklist (Slice 3 — Distribution & Polish)

Run on Windows and Linux before the `slice-3-distribution-polish` release tag.

## Theme
- [ ] Switch theme to Light → all panels respect light palette

## Keybindings
- [ ] Rebind Commit to Ctrl+S in Settings → Keybindings → shortcut works in commit textarea

## External editor
- [ ] Set external editor path → trigger merge conflict → click Open → custom editor launches

## Auto-update
- [ ] Toggle autoUpdateCheck off → no startup toast
- [ ] "Check for updates now" returns plausible result

## Revert
- [ ] Right-click commit → Revert this commit → graph shows new revert commit
- [ ] Trigger revert conflict → resolve via Conflict panel → Continue

## Status bar
- [ ] Status bar shows current branch and ahead/behind

## Packaging
- [ ] Build MSIX locally → install → app launches → uninstall
- [ ] Build AppImage on Linux → ./GitOpen-x86_64.AppImage launches
