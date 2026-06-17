# Repository Folders & Reordering — Design

**Date:** 2026-06-17
**Status:** approved
**Owner:** zN3utr4l

## Context

Cloned/opened repositories ("workspaces") are presented as a **flat list** in the
title-bar dropdown (`lib/ui/shell/repo_selector.dart`, a `MenuAnchor`). There is no
way to reorder them or group them.

Current state of the moving parts:

- **`Repositories` Drift table** (`tables/repositories_table.dart`) already holds a
  persistent catalog of every repo ever opened: `id, path, displayName, color
  (nullable, unused), lastOpenedUtc, tabOrder, createdUtc`. `tabOrder` is written on
  insert (`= count`) but never updated; `DriftRepositoryRegistry.list()` orders by it
  yet **`list()` is not consumed by any UI** — the dropdown is driven by the open set.
- **`settings['open_workspaces']` JSON** holds the *currently open* repo paths. On
  startup `main.dart::_rehydrate` opens each (in saved order) into
  `WorkspaceManager` and sets the active repo to `workspaces.first`.
  `_subscribePersistence` re-saves the open paths whenever the list changes.
- **`WorkspaceManager`** (`StateNotifier<List<Workspace>>`) holds the open set and
  already has an **unwired** `reorder(List<RepoId>)` that only mutates in-memory state.
- **"Close" (`✕`)** removes a repo from the open set only; the catalog row survives.
- **Auto-refresh / watcher** (`repo_auto_refresh_scope.dart`) is scoped to the
  **single active repo**, not the open set — confirmed: removing the "open set"
  concept does not affect watching.

## Goal

Turn the repo dropdown into a **persistent, organizable catalog**: every known repo
appears in a collapsible **nested-folder tree**; the user can **drag** repos within
and between folders and **reorder/reparent folders themselves**; the organization and
order **persist across sessions**. One repo is *active* at a time (the viewed one),
restored on startup.

## Scope decisions (owner, 2026-06-17)

1. **Persistent catalog model.** The dropdown lists *all* repos in the catalog,
   organized into folders. Selecting one makes it active. Selection does not "open"
   in the old sense — there is a single active repo, persisted as last-active.
2. **Nested folders** (tree, arbitrary depth) — not flat.
3. **Reorderable: repos *and* folders.** Drag a repo within its folder, across
   folders, or to the root; drag a folder to reorder it or reparent it under another
   folder (cycles forbidden).
4. **"Close" becomes "Remove from GitOpen"** — forgets the repo from the catalog;
   **never touches the disk**. Removing a *folder* is non-destructive: its children
   (subfolders + repos) move up to the folder's parent; only the folder node is
   deleted.
5. **`open_workspaces` JSON is retired**, replaced by a `last_active_repo` setting.
   A one-time migration seeds the catalog ordering from existing data (below).

### Non-goals (YAGNI)

- No multi-select drag (one node at a time).
- No folder colors/icons (the unused `color` column stays unused; revisit later).
- No cross-machine/cloud sync of the organization.
- No "delete from disk" action.
- No search/filter box in the dropdown (separate future feature).

## Data model

**New `folders` table** (`lib/infrastructure/persistence/tables/folders_table.dart`):

| column      | type            | notes                                            |
|-------------|-----------------|--------------------------------------------------|
| `id`        | TEXT (32) PK    | `FolderId` value, generated like `RepoId.newId()`|
| `name`      | TEXT            | user-visible name                                |
| `parentId`  | TEXT NULL       | parent folder `id`; `NULL` = root                |
| `sortOrder` | INT             | order **within its parent** (shared space)       |
| `collapsed` | INT (bool)      | expand/collapse state, persisted                 |
| `createdUtc`| DateTime        | as text (matches existing `storeDateTimeAsText`) |

**`Repositories` table change:** add `parentFolderId` TEXT NULL (`NULL` = root). The
existing **`tabOrder`** column is **repurposed** as the repo's `sortOrder` *within its
parent folder* (kept under the same column name to avoid a rename migration; its
meaning is documented in the table).

**Shared ordering space.** Within any parent (a `folderId`, or `NULL` for root) the
ordered children are the union of `folders WHERE parentId = X` and `repositories WHERE
parentFolderId = X`, sorted by their `sortOrder`/`tabOrder` in **one shared integer
sequence**. Reorder/reparent **resequences the affected parent's children to a dense
`0..n-1`** and writes back to both tables in a transaction. This lets folders and
repos interleave freely in the same list.

### Migration (`schemaVersion` 2 → 3)

In `database.dart` `onUpgrade` (and `onCreate` for fresh installs via the schema):

1. Create the `folders` table.
2. `ALTER TABLE repositories ADD COLUMN parent_folder_id TEXT NULL`.
3. **Backfill:** existing repos keep their current `tabOrder` as the root-level order
   (`parentFolderId` stays NULL). No folders are created.
4. Seed `last_active_repo` from the first entry of `open_workspaces` if present (best
   effort); leave `open_workspaces` untouched on disk (ignored henceforth).

Migrations are append-only and tested against the prior schema (see Testing).

## Domain & application layers

**Domain** (`lib/domain/repositories/`):
- `FolderId` — value object mirroring `RepoId` (`newId()`, equality).
- `Folder` — `id, name, parentId, sortOrder, collapsed` (Equatable).

**Application** (`lib/application/workspaces/`):
- `RepoTreeNode` — sealed type: `FolderNode(Folder folder, List<RepoTreeNode>
  children)` | `RepoNode(RepoLocation location, int sortOrder)`.
- `buildRepoTree(List<Folder> folders, List<RepoEntry> repos) -> List<RepoTreeNode>`
  — **pure** function returning root-level nodes, children sorted by the shared
  `sortOrder`. Defensive: a folder whose `parentId` points to a missing/removed
  folder is **re-rooted**; a `parentId` chain that would form a **cycle** is broken by
  re-rooting the offending folder. (`RepoEntry` = repo location + its placement
  `parentFolderId`/`tabOrder`.)
- `RepoTreeStore` (interface, `repo_tree_store.dart`) — persistence port for the tree:
  `createFolder(name, parentId)`, `renameFolder(id, name)`,
  `removeFolder(id)` *(re-parents children to grandparent)*,
  `setCollapsed(id, bool)`,
  `moveRepo(RepoId, toParent: FolderId?, atIndex)`,
  `moveFolder(FolderId, toParent: FolderId?, atIndex)`,
  `loadFolders()`, `loadRepoPlacements()`. Implemented by a Drift class beside
  `DriftRepositoryRegistry`, sharing `AppDatabase`. `RepositoryRegistry` keeps its
  current identity responsibilities (`add/list/remove/touchLastOpened`); `list()` now
  also surfaces `parentFolderId`/`tabOrder` for tree building.
- **`WorkspaceManager` becomes catalog-backed:** its state is the full catalog of
  repos (loaded from the registry on startup), not a session "open set". `open(path)`
  still adds-to-catalog-if-new + returns the workspace (caller sets it active);
  the old `close()` is replaced by `remove(RepoId)` (delete from catalog). The unwired
  `reorder` is removed in favor of the tree ops.
- **`RepoOrganizer`** (StateNotifier exposing `List<RepoTreeNode>`): the single source
  the dropdown watches. Wraps `RepoTreeStore` + the catalog; each mutation persists
  then rebuilds the tree. Reordering is optimistic (update state, then persist; on
  persist failure, reload from store and surface a SnackBar).
- **Active repo** moves to a persisted `last_active_repo` setting (read on startup by
  `_rehydrate`, written when `activeWorkspaceIdProvider` changes). `activeWorkspaceId`
  stays a `StateProvider<RepoId?>`.

## UI

`repo_selector.dart` keeps its **title-bar button** (shows active repo name) but the
dropdown body is replaced. `MenuAnchor`/`MenuItemButton` cannot host drag-reorder of a
nested tree, so the dropdown opens a **custom popover** (`OverlayPortal` anchored to
the button, dismiss on outside-tap / `Esc`) containing:

- A **scrollable tree** built from `repoOrganizerProvider`, rendered as a **flattened
  list of visible rows** (a folder's descendants are hidden when collapsed). Each row:
  indent by depth; folder rows show a disclosure chevron + name + child count and a
  drag handle; repo rows show name + path + active check (`✓`) + a row hover menu
  (Remove from GitOpen, Move to…). The existing per-row palette/hover styling is
  reused.
- **Drag & drop**, hand-built (no new package, consistent with the project's
  hand-rolled commit graph): each row is a `Draggable<NodeRef>`; between/onto rows are
  `DragTarget`s yielding three drop intents — **before row**, **after row**, and
  **into folder** (when hovering a folder's label). A thin insertion line / folder
  highlight signals the target. Drop calls `moveRepo`/`moveFolder` with the computed
  `(parent, index)`. Dragging a folder onto its own descendant is rejected (no-op).
- **Footer actions** (kept from today): *New folder* (inline name field, created at
  root or inside the right-clicked folder), *Open repository…*, *Open folder of
  repos…*, *Clone…*.
- **Expand/collapse** persists via `setCollapsed`.
- **Welcome screen** unchanged (shown when the catalog is empty).

Keybinding `Ctrl+T` (`openRepoSelector`) keeps opening the popover.

## Error handling & edge cases

- **Missing path on activation:** selecting a repo whose folder no longer exists on
  disk surfaces a SnackBar and offers *Remove from GitOpen*; it does not crash the
  active-repo view (same defensive posture as today's rehydrate).
- **Cycle / orphan folders:** broken defensively in `buildRepoTree` (re-root), so a
  corrupt DB can never produce an infinite tree.
- **Reparent onto descendant:** rejected at the drop layer *and* guarded in
  `moveFolder` (walk up the target's ancestry; abort if the dragged id appears).
- **Concurrent resequence:** all reorder/reparent/remove writes run inside a Drift
  transaction so the shared `sortOrder` space stays dense and consistent.
- **Persist failure:** optimistic UI rolls back by reloading from the store; user sees
  a non-fatal SnackBar.
- **Remove active repo:** after removal, active falls back to the first remaining
  catalog repo (or null → welcome screen), mirroring today's `_close` fallback.

## Files

- **Add:** `lib/infrastructure/persistence/tables/folders_table.dart`
- **Add:** `lib/domain/repositories/folder_id.dart`, `.../folder.dart`
- **Add:** `lib/application/workspaces/repo_tree_node.dart` (+ `build_repo_tree.dart`),
  `repo_tree_store.dart`, `repo_organizer.dart`
- **Add:** `lib/infrastructure/persistence/repo_tree_store_impl.dart`
- **Add:** `lib/ui/shell/repo_tree_popover.dart` (+ row widgets / drag helpers)
- **Modify:** `tables/repositories_table.dart` (+`parentFolderId`, doc `tabOrder`),
  `database.dart` (schema v3 + migration), `repository_registry_impl.dart`
  (surface placement), `workspace_manager.dart` (catalog-backed; `remove`),
  `providers.dart` (new providers), `main.dart` (`_rehydrate`/persistence → catalog +
  `last_active_repo`), `repo_selector.dart` (popover), `workspace_persistence*.dart`
  (retire / replace with last-active setting).
- **Add tests** mirroring existing suites (see below).
- **Modify:** `pubspec.yaml` version bump (CD publishes).

Drift codegen (`database.g.dart`) is regenerated via `build_runner` after the table
changes.

## Testing / verification

Follows the existing layered suites (`test/...` mirrors `lib/...`;
`test/_helpers/in_memory_db.dart` provides `newInMemoryDb()`):

- **Pure unit (no Flutter):** `build_repo_tree` — nesting, shared-order interleave of
  folders+repos, orphan re-rooting, cycle breaking. Highest-value, fastest tests.
- **Persistence:** `RepoTreeStore` impl — create/rename/remove(folder re-parents
  children), `moveRepo`/`moveFolder` resequencing to dense `0..n-1`, reparent-onto-
  descendant guard. Plus a **migration test** (v2 DB → v3) asserting backfill keeps
  existing repos at root in their prior `tabOrder`.
- **WorkspaceManager / catalog:** load-all-on-start, `remove`, active fallback.
- **Widget:** `repo_tree_popover` — renders nested tree, collapse hides descendants,
  a simulated drag reorders and calls the store, "Remove from GitOpen" path.
- **Gate:** `flutter analyze` + `flutter test` green (PR CI runs exactly these). Manual
  smoke on Windows (`flutter run`): create folders, drag repos/folders, restart and
  confirm the tree + active repo are restored.

## Risks / notes

- **Hand-built tree DnD is the largest risk.** Mitigation: flatten-visible-rows +
  `Draggable`/`DragTarget` is a well-trodden Flutter pattern; build it behind the
  `RepoOrganizer` interface so the persistence/order logic is unit-tested independently
  of the gesture layer. If gesture polish proves expensive, a fallback is a right-click
  *Move to…* menu (already specced as the row menu) which exercises the same store ops
  without drag.
- **Shared `sortOrder` across two tables** is the subtle correctness point; the dense-
  resequence-in-a-transaction rule plus persistence tests contain it.
- **Behavioral shift** (catalog vs open-set, close→remove) changes muscle memory; it is
  the explicit owner decision above and is the natural model for "organize cloned
  repos". `last_active_repo` preserves single-active-repo restore.
- Reusing `tabOrder` instead of renaming avoids a fragile column-rename migration at
  the cost of a slightly stale name; documented in the table.
