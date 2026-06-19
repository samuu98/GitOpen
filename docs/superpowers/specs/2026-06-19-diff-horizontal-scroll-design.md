# Diff horizontal scrolling — design

**Date:** 2026-06-19
**Status:** Approved (design)

## Problem

In the bottom panel's **Changes** view, long diff lines are cut off and
unreachable. The line content is rendered inside an `Expanded` widget with
`softWrap: false` and `overflow: TextOverflow.clip` (or `ellipsis`), so anything
wider than the panel is silently dropped — there is no way to read it.

This affects three rendering paths, all of which share the same root cause:

| View | File | Renderer | Current overflow |
|---|---|---|---|
| Commit diff ("Changes" tab) | `lib/ui/bottom_panel/diff_view.dart` → `HunkLines` | `DiffLineRow` | `clip` |
| Side-by-side (Split toggle) | `lib/ui/common/diff_line_row.dart` | `_SplitCell` | `clip` |
| Working-copy preview (local changes) | `lib/ui/working_copy/hunk_row.dart` | `_HunkLineRow` | `ellipsis` |

## Goal

Long lines become reachable via **horizontal scrolling** (a scrollbar at the
bottom of the diff region). The line-number gutter scrolls together with the
content. No content is clipped.

Out of scope: the **File Tree** tab stays exactly as it is. Line wrapping
(soft-wrap) is explicitly *not* the chosen behaviour.

## Approach

Two coordinated changes.

### 1. Render line content at its natural width

In each line renderer, the content `Text` stops being `Expanded` and is no
longer clipped — it is sized to its own content with `softWrap: false`. The
row background tint (`+`/`-` colouring) must still span the full width; this is
achieved by the scroll container below stretching every row to the widest row's
width.

### 2. Shared horizontal-scroll container

A small reusable widget — working name `DiffHorizontalScroll` — wraps a column
of diff rows:

```
LayoutBuilder(builder: (context, constraints) =>
  Scrollbar(                       // horizontal, thumbVisibility: true
    controller: controller,
    child: SingleChildScrollView(
      controller: controller,
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: constraints.maxWidth),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,         // the diff line rows
          ),
        ),
      ),
    ),
  ))
```

Why each piece:
- `IntrinsicWidth` sizes the column to the widest row, so every row (and its
  background) extends to the full content width — backgrounds stay filled while
  scrolled right.
- `crossAxisAlignment.stretch` makes shorter rows fill that width too.
- `ConstrainedBox(minWidth: viewport)` fills the panel when content is short, so
  no scrollbar appears and backgrounds reach the right edge as today.
- A single horizontal `ScrollController` per region drives both the
  `SingleChildScrollView` and the visible `Scrollbar`.

### Scroll region boundaries

The scroll wraps only a hunk's **code lines**. File/hunk headers, the
selection checkboxes' hunk header, and the discard/unstage action button stay
fixed — they use `Expanded`/full-width layout that cannot live inside an
unbounded horizontal scroll, and keeping them fixed is also the better UX.

| View | Scroll boundary |
|---|---|
| Commit diff | **Per hunk** — wrap the line column inside `HunkLines`. The hunk's `@@` header (rendered by `_hunk` in `diff_view.dart`) stays fixed above it. |
| Working-copy preview | **Per hunk** — wrap the `_HunkLineRow` list inside `HunkRow`. The hunk header row (checkbox + `@@` + discard/unstage) stays fixed. |
| Side-by-side | **Per hunk** — wrap the whole split structure in `SplitHunkLines`; both sides scroll together. |

## Design decisions

- **Working-copy checkboxes scroll with the content.** In `_HunkLineRow` the
  left "gutter" is the per-line selection checkbox + `+`/`-` prefix. Consistent
  with the gutter-scrolls-with-content choice, these scroll horizontally along
  with the line. Accepted trade-off: when scrolled far right the checkboxes move
  off-screen; the user scrolls back left to toggle. (Alternative — freezing the
  checkbox gutter — was considered and rejected for consistency and simplicity.)
- **Performance.** `IntrinsicWidth` adds an extra layout pass over the rows.
  Diffs are already capped/truncated (`diff_cap`, `TruncatedDiffBanner`), so the
  row count per region is bounded and this is acceptable. Fallback if it ever
  regresses: precompute the widest line with a `TextPainter` and use a fixed
  width instead of `IntrinsicWidth`.

## Components / boundaries

- `DiffHorizontalScroll` (new, `lib/ui/common/`): takes the list of row widgets,
  owns the `ScrollController`, renders the scroll + scrollbar + intrinsic-width
  column. One clear job: make a vertical stack of rows horizontally scrollable
  with full-width row backgrounds. Used by all three call sites.
- `DiffLineRow` / `_SplitCell` (`diff_line_row.dart`): content `Text` becomes
  natural-width, non-clipped. No behavioural change beyond width.
- `HunkLines` (`diff_line_row.dart`): wraps its unified line column in
  `DiffHorizontalScroll(IntrinsicWidth(Column(stretch, …)))`.
- `SplitHunkLines` (`diff_line_row.dart`): replaces the two `Expanded` cells
  with a `Table` whose two content columns use `IntrinsicColumnWidth` (so the
  sides align across all rows and row heights size automatically, with no text
  measurement) and a 1px `FixedColumnWidth` divider column; the whole table is
  wrapped in `DiffHorizontalScroll`. Accepted cosmetic trade-off: short
  side-by-side diffs no longer stretch to fill the pane.
- `_HunkLineRow` / `HunkRow` (`hunk_row.dart`): same width change; the line
  list is wrapped in `DiffHorizontalScroll`; checkboxes/prefix/header unchanged.

## Error / edge handling

- Empty / very short diffs: `minWidth` fills the viewport, no scrollbar, looks
  identical to today.
- Binary / image diffs: unchanged (they don't go through the line renderers).
- Word-diff and ignore-whitespace toggles: orthogonal — they affect span
  building, not layout width.

## Testing

Widget tests (one per concern, reusing existing diff test fixtures where
available):
1. A very long line is **not clipped** — its trailing text is present in the
   render tree and reachable by scrolling the `SingleChildScrollView`.
2. Short content shows **no horizontal scrollbar** and the row background fills
   the viewport width.
3. Row background (addition/deletion tint) **spans the full content width** when
   the widest line exceeds the viewport.
4. Side-by-side: a long line makes the hunk horizontally scrollable.

Manual check: run the app, open a commit with long lines in **Changes**, and a
working-copy file with long lines; confirm horizontal scrolling in both unified
and split modes.
