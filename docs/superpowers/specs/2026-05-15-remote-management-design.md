# Remote management (add / edit / rename / remove / fetch)

**Date:** 2026-05-15
**Status:** approved
**Slice:** GitOpen — remote CRUD

## Problem

GitOpen mostra i remote in sola lettura. Manca il flow tipico "ho un repo locale, voglio agganciarlo a un remote" e l'editing di URL/nome dei remote già esistenti.

## Scope

In:
- `git remote add <name> <url>`
- `git remote remove <name>`
- `git remote rename <old> <new>`
- `git remote set-url <name> <url>`
- Fetch del singolo remote (l'API esiste già — solo voce di menu)

Out:
- Push-url separato da fetch-url
- Multipli URL per remote
- Tracking-branch defaults

## Architettura

### Domain / interface

`lib/application/git/git_write_operations.dart` — 4 nuovi metodi:

```dart
Future<GitResult<void>> addRemote(RepoLocation r, String name, String url);
Future<GitResult<void>> removeRemote(RepoLocation r, String name);
Future<GitResult<void>> renameRemote(RepoLocation r, String oldName, String newName);
Future<GitResult<void>> setRemoteUrl(RepoLocation r, String name, String url);
```

### Infrastructure

`lib/infrastructure/git/git_cli_write_operations.dart`:
- `addRemote` → `git remote add <name> <url>`
- `removeRemote` → `git remote remove <name>`
- `renameRemote` → `git remote rename <old> <new>`
- `setRemoteUrl` → `git remote set-url <name> <url>`

Stesso pattern try/catch + `_classify` di tutti gli altri metodi sincroni. Nessun progress stream.

### UI

**Dialog unico** `lib/ui/dialogs/remote_dialog.dart` (nuovo) — parametrico via enum `RemoteDialogMode { add, editUrl, rename }`:
- `add`: campi `name` + `url`
- `editUrl`: solo `url` (name read-only)
- `rename`: solo `name`

Stile e validazione mutuati da `branch_create_dialog.dart`. Ritorna i nuovi valori o `null` se cancellato.

**Sidebar** `lib/ui/sidebar/sidebar.dart`:

1. Header `_Section("REMOTES", …)` esteso con trailing widget opzionale → `IconButton` "+" che apre `RemoteDialog(mode: add)`.
2. Empty state: invece di `_EmptyHint('No remotes')` mostro un bottone "Add remote…" centrato.
3. Nuovo widget `_RemoteHeaderRow` (sostituisce il `Padding`/`Text` attuale del nome remote): wrappato in `GestureDetector` con `onSecondaryTapDown` → menu:
   - **Fetch**
   - **Edit URL…** (mostra URL corrente prepopolato)
   - **Rename…**
   - divider
   - **Remove** (ConfirmDialog, danger)

Dopo ogni op: `ref.invalidate(_sidebarDataProvider(repo))`.

### Estensione `_Section`

Il widget `_Section` privato della sidebar oggi accetta solo `title` e `child`. Aggiungo parametro opzionale `Widget? trailing` per ospitare il "+" del REMOTES. Non rompe gli altri call site.

## Error handling

- Nome duplicato in add → git restituisce stderr "remote * already exists" → mostriamo come è (toast/snackbar via flow esistente, se presente; altrimenti `ConfirmDialog`-like info dialog). Vedere come `_TagRow` gestisce errori di delete (oggi swallow → in linea con esso per ora).
- URL malformato: lasciamo che git fallisca e mostriamo lo stderr classificato `GitErrorKind.other`.
- Validazione client: nome non vuoto, URL non vuoto, nome non contiene spazi.

## Testing

Niente test scritti — il progetto non ha al momento test su `git_cli_write_operations.dart` (verificato: nessun file `*_test.dart` referenzia queste write ops). In linea con la prassi della slice precedente. Verifica manuale:

1. Repo locale senza remote → "Add remote…" da empty state → compare nella lista.
2. Right-click su remote → Edit URL → verificare con `git remote -v` dal terminale.
3. Right-click → Rename → ramo tracking si aggiorna al refresh.
4. Right-click → Remove → conferma → remote sparisce.
5. Right-click → Fetch → progress visibile (riusa stream esistente).

## File toccati

Nuovi:
- `lib/ui/dialogs/remote_dialog.dart`

Modificati:
- `lib/application/git/git_write_operations.dart`
- `lib/infrastructure/git/git_cli_write_operations.dart`
- `lib/ui/sidebar/sidebar.dart`
