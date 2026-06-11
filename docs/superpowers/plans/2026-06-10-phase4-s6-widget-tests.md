# Phase 4 — S6 Widget Tests Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or superpowers:test-driven-development for each test block.

**Goal:** Add targeted widget coverage around the graph, sidebar, and working-copy rows without introducing real-git UI tests.

**Branch:** `feat/phase4-s6-widget-tests` from `origin/main` after S5. Version stays `0.1.17+18`; this is test-only.

## Tasks

- [x] **Task 1: Graph widgets**
  - Add widget tests for `CommitRow` rendering/tap/semantics.
  - Add widget tests for `LocalChangesRow` rendering and navigation to the changes view.

- [x] **Task 2: Sidebar widgets**
  - Add widget tests for `BranchTreeView` folder collapse and visibility toggle state.
  - Add widget tests for `StashRow` reveal semantics/state.

- [x] **Task 3: Working-copy widgets**
  - Add widget tests for `FileList`/`FileRow` rendering, selection, and semantics for staged/unstaged rows.

- [x] **Task 4: Verification and PR**
  - Run targeted widget tests, full `flutter test -j 2`, `flutter analyze`, and `git diff --check`.
  - Commit, push, open PR, merge on green.
