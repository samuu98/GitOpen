# GitHub Actions management in-client — design

**Date:** 2026-06-19
**Status:** Draft — awaiting approval
**Goal:** Manage GitHub Actions from GitOpen without opening the website —
rerun, cancel, live monitor, drill into a run's jobs and steps, and view logs.
All in one PR.

## Today

`actions_tab.dart` is read-only: it lists workflow runs for the current branch
(status icon, name, branch, duration) with an "Open on GitHub" button. The
`GitHubApi` port exposes only `listWorkflowRuns`. No rerun, cancel, jobs, steps,
or logs.

## Scope (one PR)

1. **Run actions** — rerun all jobs, rerun only failed jobs, cancel a run.
2. **Live monitor** — while a run is `queued`/`in_progress`, auto-refresh the
   list (and the open run detail) every few seconds; stop when completed.
3. **Run detail** — open a run → its jobs; each job lists its steps with
   status / conclusion / duration.
4. **Logs** — per-**job** log text on demand (see decision L below).

## API additions (`GitHubApi` + `GitHubRestApi`)

- `Future<void> rerunWorkflowRun(RepoSlug, int runId, {required String token})`
  → `POST /repos/{o}/{r}/actions/runs/{id}/rerun`
- `Future<void> rerunFailedJobs(RepoSlug, int runId, {required String token})`
  → `POST /repos/{o}/{r}/actions/runs/{id}/rerun-failed-jobs`
- `Future<void> cancelWorkflowRun(RepoSlug, int runId, {required String token})`
  → `POST /repos/{o}/{r}/actions/runs/{id}/cancel`
- `Future<List<WorkflowJob>> listWorkflowJobs(RepoSlug, int runId, {required String token})`
  → `GET /repos/{o}/{r}/actions/runs/{id}/jobs`
- `Future<String> jobLogs(RepoSlug, int jobId, {required String token})`
  → `GET /repos/{o}/{r}/actions/jobs/{id}/logs` (redirect-safe, see L)

## Models (`github_models.dart`)

```
WorkflowJob: id, name, status, conclusion?, startedAt?, completedAt?,
             htmlUrl, List<WorkflowStep> steps
WorkflowStep: name, status, conclusion?, number, startedAt?, completedAt?
```
Both reuse the existing run status/conclusion vocabulary
(`queued`/`in_progress`/`completed`; `success`/`failure`/`cancelled`/`skipped`…).

## Decisions to confirm

**Decision L — logs granularity.** GitHub REST has **no per-step log
endpoint**. `GET …/jobs/{id}/logs` returns a 302 to a signed blob holding that
**job's full log as plain text** (steps delimited by `##[group]` markers, not a
clean API). Proposal: show **per-job logs** (full text, in a monospace viewer
opened from each job), and rely on the **per-step status list** (from the jobs
API) for "which step failed". No per-step log splitting (fragile), no live log
streaming (REST can't — GitHub's site uses a private socket). Live *status*
still updates via polling; logs are fetched on demand.

**Decision R — redirect/auth.** The logs request must be done manually:
`followRedirects: false`, send `Authorization`; on 302 read `Location` and GET
it **without** the auth header (signed URL rejects it). Mirrors the existing
release-asset download path.

**Decision P — poll interval.** Auto-refresh every **5s** while any run (or the
open run's jobs) is non-terminal; stop when all terminal. (5s keeps the prompt
cache window irrelevant here — it's network polling, not model calls.)

## UI

- **Run row** (`actions_tab.dart`): add a kebab/inline actions — Rerun, Rerun
  failed (only when the run failed), Cancel (only when in progress) — plus the
  existing Open-on-GitHub. Clicking the row opens the detail.
- **Run detail** (new `workflow_run_detail_view.dart`): header (name, status,
  branch, duration) + jobs list; each job expandable to its steps (icon +
  name + duration); each job has a "View logs" affordance → log viewer.
- **Log viewer** (new, or a dialog): monospace, scrollable (horizontal +
  vertical), with copy. Handles "logs not available yet" for running jobs.
- **Auto-refresh**: a polling provider re-fetches runs / jobs while non-terminal
  (reuse the `skipLoadingOnReload` pattern so the view doesn't flicker).

## Testing

- API: `MockClient` asserts each new endpoint's method/path; `listWorkflowJobs`
  parses jobs+steps; `jobLogs` follows the 302 and drops auth on the redirect.
- Models: status/conclusion → display mapping is pure + tested.
- UI: run row shows Cancel only while in progress / Rerun-failed only on
  failure; tapping a run shows its jobs and steps; tapping a job fetches logs.
- Poll: a fake clock / pump advances and re-fetches while non-terminal, stops
  when terminal (model the existing watcher/debouncer test style).

## Out of scope (this PR)

Live log streaming; artifacts download; per-step logs; triggering
`workflow_dispatch` with inputs; matrix-job grouping niceties.
