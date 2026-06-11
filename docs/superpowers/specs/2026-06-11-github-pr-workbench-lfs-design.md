# GitHub PR Workbench + Git LFS Daily Driver Design

## Goal

Make GitOpen a stronger daily-driver Git client by adding two large but
focused capabilities:

1. A GitHub-only PR workbench with PR creation, detail, files/diff review,
   line-level review comments, review submission, close/reopen, draft-ready,
   and merge actions.
2. A Git LFS daily-driver view with local repository setup, tracked pattern
   management, LFS file listing, and LFS fetch/pull/push operations.

This is intentionally **GitHub-only** for PR features. GitLab, Bitbucket, Azure
DevOps, LFS locks, LFS prune, and LFS migration are out of scope for this slice.

## Current Context

GitOpen already has:

- `GitHubApi` in `lib/application/github/github_api.dart`.
- `GitHubRestApi` in `lib/infrastructure/github/github_rest_api.dart`.
- `GitHubPanel` in `lib/ui/github/github_panel.dart` with Pull Requests and
  Actions tabs.
- `githubSlugProvider`, `gitHubApiProvider`, and `repoActiveProfileProvider` in
  `lib/application/providers.dart`.
- `GitActionsService` and `GitActionsController` for local git operations with
  progress and auth retry.
- A CLI-based git architecture with application ports and infrastructure
  adapters.

The new design should extend those seams instead of introducing a second GitHub
or git execution path.

References:

- GitHub REST Pull Requests:
  https://docs.github.com/en/rest/pulls/pulls
- GitHub REST Pull Request Reviews:
  https://docs.github.com/rest/pulls/reviews
- GitHub REST Pull Request Review Comments:
  https://docs.github.com/rest/pulls/comments
- Git LFS overview:
  https://git-lfs.com/

## Non-Goals

- No GitLab/Bitbucket provider abstraction in this slice.
- No GraphQL dependency unless REST cannot support a required operation.
- No full GitHub Issues client.
- No LFS locking, unlock, prune, migrate, import, or storage quota UX.
- No global `git lfs install` action. GitOpen may run only repository-local
  setup via `git lfs install --local`.
- No background sync daemon for PRs or LFS.

## Architecture

### GitHub Application Layer

Extend `GitHubApi` rather than creating a new PR-specific port. The application
layer owns typed requests, immutable models, and typed errors.

Add models:

- `PullRequestDetail`
  - `number`, `title`, `body`, `author`, `state`, `isDraft`, `mergeable`,
    `mergeStateStatus`, `baseRef`, `headRef`, `headSha`, `htmlUrl`,
    `createdAt`, `updatedAt`.
- `PullRequestFile`
  - `filename`, `status`, `additions`, `deletions`, `changes`, `patch`.
- `PullRequestReview`
  - `id`, `user`, `state`, `body`, `submittedAt`, `htmlUrl`.
- `PullRequestComment`
  - `id`, `user`, `body`, `path`, `line`, `side`, `position`,
    `inReplyToId`, `createdAt`, `updatedAt`, `htmlUrl`.
- `IssueCommentInfo`
  - PR timeline/conversation comments via the Issues comments API.
- `CreatePullRequestRequest`
  - `title`, `body`, `head`, `base`, `draft`.
- `UpdatePullRequestRequest`
  - optional `title`, `body`, `state`, `base`, `maintainerCanModify`.
- `SubmitReviewRequest`
  - `event` (`COMMENT`, `APPROVE`, `REQUEST_CHANGES`), optional `body`, queued
    `DraftReviewComment`s.
- `MergePullRequestRequest`
  - `commitTitle`, `commitMessage`, `method` (`merge`, `squash`, `rebase`).

Extend `GitHubApi`:

- `getPullRequest(slug, number, token)`
- `listPullRequestFiles(slug, number, token)`
- `listPullRequestReviews(slug, number, token)`
- `listPullRequestReviewComments(slug, number, token)`
- `listPullRequestIssueComments(slug, number, token)`
- `createPullRequest(slug, request, token)`
- `updatePullRequest(slug, number, request, token)`
- `markPullRequestReadyForReview(slug, number, token)`
- `mergePullRequest(slug, number, request, token)`
- `createIssueComment(slug, number, body, token)`
- `createReview(slug, number, request, token)`
- `createReviewCommentReply(slug, number, commentId, body, token)`

`GitHubApiException` gains additional kinds:

- `validation`
- `conflict`
- `mergeBlocked`

Existing kinds remain:

- `auth`
- `rateLimit`
- `network`
- `notFound`

### GitHub Infrastructure Layer

`GitHubRestApi` implements the new methods with the same injectable
`http.Client` pattern already used by the current tests.

REST mapping:

- Pull requests: create/list/get/update/merge via `/repos/{owner}/{repo}/pulls`.
- Reviews via `/repos/{owner}/{repo}/pulls/{pull_number}/reviews`.
- Review comments via
  `/repos/{owner}/{repo}/pulls/{pull_number}/comments`.
- Conversation comments via
  `/repos/{owner}/{repo}/issues/{issue_number}/comments`.
- Files via `/repos/{owner}/{repo}/pulls/{pull_number}/files`.
- Ready-for-review uses GitHub's endpoint if available in REST for the current
  API version; if REST support is insufficient, this specific action may use a
  narrow GraphQL helper inside the GitHub infrastructure package. The
  application port remains the same.

HTTP status mapping:

- `401` -> auth
- `403` with rate-limit remaining `0` -> rateLimit
- `403` otherwise -> auth
- `404` -> notFound
- `409` -> conflict
- `422` -> validation
- merge responses indicating blocked/dirty/unstable -> mergeBlocked
- other non-2xx/transport failures -> network

### Git LFS Application Layer

Add a dedicated `GitLfsOperations` port in `lib/application/git_lfs/`.

Models:

- `GitLfsStatus`
  - `isInstalled`, `version`, `isRepoConfigured`, `hasAttributes`.
- `GitLfsTrackedPattern`
  - `pattern`, `attributes`, `source`.
- `GitLfsFile`
  - `oid`, `path`, `sizeLabel`.

Port:

- `Future<GitLfsStatus> status(RepoLocation repo)`
- `Future<List<GitLfsTrackedPattern>> trackedPatterns(RepoLocation repo)`
- `Future<List<GitLfsFile>> files(RepoLocation repo)`
- `Future<GitResult<void>> installLocal(RepoLocation repo)`
- `Future<GitResult<void>> track(RepoLocation repo, String pattern)`
- `Future<GitResult<void>> untrack(RepoLocation repo, String pattern)`
- `Stream<GitProgress> fetch(RepoLocation repo, {AuthSpec? auth})`
- `Stream<GitProgress> pull(RepoLocation repo, {AuthSpec? auth})`
- `Stream<GitProgress> push(RepoLocation repo, {AuthSpec? auth})`

The LFS port is separate from `GitWriteOperations` because LFS has its own
read/write surface and typed status. Long-running sync commands still use
`GitProgress` so they can feed the existing operation UI.

### Git LFS Infrastructure Layer

Add `GitCliLfsOperations` in `lib/infrastructure/git_lfs/`.

CLI commands:

- `git lfs version`
- `git lfs install --local`
- `git lfs track --list`
- `git lfs track <pattern>`
- `git lfs untrack <pattern>`
- `git lfs ls-files --long --size`
- `git lfs fetch`
- `git lfs pull`
- `git lfs push origin`

Missing LFS binary is not an exception leak. It maps to
`GitLfsStatus(isInstalled: false, ...)` and user-facing states explain that Git
LFS must be installed externally.

Parsing helpers should be pure and tested separately:

- `parseGitLfsVersion`
- `parseGitLfsTrackList`
- `parseGitLfsLsFiles`

## UI Design

### GitHub Workbench

The current GitHub panel becomes a workbench rather than a two-list panel.

Layout:

- Top tabs remain `Pull Requests` and `Actions`.
- Pull Requests tab becomes split:
  - left rail/list: PRs, search/filter later, selection state now;
  - right detail area: selected PR detail.
- On narrower widths, use a stacked layout: list above detail.

PR list:

- Shows number, title, draft badge, author, updated date, checks chip.
- Quick actions:
  - checkout PR as `pr/<number>`
  - open on GitHub
  - refresh

PR detail:

- Header:
  - title, state/draft badge, author, base/head refs, checks, mergeability.
- Body:
  - markdown/plain body rendered as selectable text for this slice.
- Actions:
  - edit title/body
  - close/reopen
  - mark ready for review when draft
  - merge with method selector (`merge`, `squash`, `rebase`)

Create PR:

- Button appears when current branch is not the default branch and the repo is
  GitHub-backed.
- Dialog fields:
  - title
  - body
  - base branch
  - head branch
  - draft toggle
- On success, select the newly created PR and invalidate PR providers.

Files/diff:

- File list shows filename, status, additions/deletions.
- Selecting a file shows the GitHub patch text.
- Inline diff rendering can initially reuse existing diff row styling where
  practical, but it should not force GitHub patch text through staging-specific
  patch application paths.
- Each commentable line exposes a small comment affordance.

Review drawer:

- A queued review can contain:
  - top-level body
  - line-level draft comments
  - event: comment, approve, request changes
- Submit review calls `createReview`.
- Existing review comments display inline when path/line mapping is available.
- General PR conversation comments appear in a timeline area.

### Git LFS View

Add `MainView.lfs` and an `LFS` segment in `ViewSelector`.

LFS is visible for every repo, not only GitHub repos.

States:

- `git lfs` not installed:
  - show version/status card and install instructions;
  - no automatic global install.
- LFS installed but repo not configured:
  - show `Install in repo` button, backed by `git lfs install --local`.
- Ready:
  - show tracked patterns, LFS files, and sync actions.

Tracked patterns:

- Dense list from `git lfs track --list`.
- Add pattern dialog.
- Remove pattern action.
- After track/untrack, invalidate pattern and status providers, and refresh
  working-copy status because `.gitattributes` changes.

LFS files:

- List from `git lfs ls-files --long --size`.
- Columns: path, oid prefix, size label.
- Empty state when no files are tracked by LFS.

Sync actions:

- `Fetch`
- `Pull`
- `Push`

Each runs through operations/progress and uses the repo's active auth profile
where possible.

## Provider/Data Flow

GitHub:

- `githubPullRequestsProvider(repo)`
- `githubPullRequestDetailProvider((repo, number))`
- `githubPullRequestFilesProvider((repo, number))`
- `githubPullRequestReviewsProvider((repo, number))`
- `githubPullRequestCommentsProvider((repo, number))`
- `githubIssueCommentsProvider((repo, number))`

All GitHub providers depend on:

- `githubSlugProvider(repo)`
- `repoActiveProfileProvider(repo)`
- `gitHubApiProvider`

No token or slug means an inline state, not a thrown widget error.

LFS:

- `gitLfsOperationsProvider`
- `gitLfsStatusProvider(repo)`
- `gitLfsTrackedPatternsProvider(repo)`
- `gitLfsFilesProvider(repo)`

Write actions invalidate the affected LFS providers and relevant git read
providers.

## Error Handling

GitHub:

- Auth failures show sign-in/account-switcher CTA.
- Rate limit shows inline retry-later state.
- Validation errors show GitHub's message if available.
- Merge blocked shows an inline mergeability message and does not close the PR.
- Review comment line mapping failures are caught before API calls when possible
  and reported next to the draft comment.

LFS:

- Missing `git lfs` binary shows a typed not-installed state.
- Nonzero command exits map to `GitFailure` or a typed LFS failure, with stderr
  preserved for user messaging.
- Network/auth failures in LFS sync commands use the same auth retry pattern as
  fetch/pull/push when the credential helper can inject auth.

## Testing Strategy

Pure tests:

- GitHub model parsing and merge status mapping.
- LFS parser tests for `version`, `track --list`, and `ls-files`.
- Review comment line mapping helpers.

REST tests:

- Create PR.
- Update PR.
- Merge PR success and blocked/conflict mapping.
- List files.
- List reviews.
- Create review with draft comments.
- Create issue comment.
- Create review comment reply.

CLI/LFS tests:

- Real-git tests for track/untrack/list patterns when `git lfs version` exists.
- Tests skip explicitly when `git lfs` is unavailable.
- Parser tests always run, independent of system LFS availability.

Widget tests:

- GitHub PR list/detail selection.
- PR create dialog validation and success state.
- PR file diff renders changed files.
- Draft review comment queue and submit buttons.
- Merge blocked inline error.
- LFS not-installed state.
- LFS repo-not-configured state.
- LFS tracked pattern add/remove flows with fake operations.
- LFS files list and empty state.

Full verification:

- `flutter test -j 2`
- `flutter analyze`
- `git diff --check`

## Implementation Tranches

This should be implemented as one feature branch but in small commits:

1. GitHub full PR models/API + REST tests.
2. GitHub PR workbench read-only detail/files/comments.
3. GitHub PR mutations: create/edit/close/reopen/ready/merge.
4. GitHub review comments and review submission.
5. Git LFS application/infrastructure + parser and CLI tests.
6. Git LFS UI + providers.
7. Full verification, version bump if required by release policy, PR.

## Risks

- GitHub line-level review comments require exact diff line metadata. Mitigate
  by isolating line mapping helpers and testing them with representative patch
  shapes.
- GitHub REST may not expose every draft/ready action uniformly. Mitigate by
  allowing a narrow infrastructure-only GraphQL fallback for ready-for-review if
  needed.
- Git LFS availability varies by machine/CI. Real LFS tests must skip when the
  binary is missing; parser tests keep coverage stable.
- The GitHub panel can become too large. Mitigate by extracting PR list,
  detail, files, comments, and review drawer widgets into focused files.
- A single "everything" branch is large. Mitigate by committing each tranche and
  running targeted tests after each one.

## Acceptance Criteria

- GitHub repos can create, inspect, review, comment on, close/reopen, and merge
  PRs from inside GitOpen.
- PR files/diffs render in-app and support line-level review comments.
- Existing PR checkout and Actions views continue to work.
- Git LFS status is visible for any repo.
- Users can configure repo-local LFS, add/remove tracked patterns, inspect LFS
  files, and run LFS fetch/pull/push.
- Missing Git LFS binary is handled as a clear UI state.
- No global Git LFS installation is performed by GitOpen.
- Full local verification passes.
