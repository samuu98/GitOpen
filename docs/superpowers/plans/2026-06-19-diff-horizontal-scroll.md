# Diff Horizontal Scrolling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make long diff lines reachable by horizontal scrolling (instead of being clipped) in all three diff renderers — unified commit diff, working-copy preview, and side-by-side.

**Architecture:** A shared `DiffHorizontalScroll` widget wraps a hunk's code lines in a horizontal `SingleChildScrollView`; a `LayoutBuilder` captures the viewport width so content still fills the pane (and row backgrounds reach the edge) when short. Line renderers stop using `Expanded`/clip and size their content to its natural width. Hunk/file headers and action buttons stay fixed.

**Tech Stack:** Flutter, flutter_riverpod, flutter_test (widget tests). Lints: `very_good_analysis`.

## Global Constraints

- Dart SDK floor: `^3.11.5` (collection-`indexed`, records/patterns are available and already used).
- Lint package: `very_good_analysis` — prefer `const`, `final` locals, single quotes, trailing commas, dispose controllers/painters.
- Git identity for this repo: `zN3utr4l` (already set). Work on branch `feat/diff-horizontal-scroll`.
- Theme in widget tests: `MaterialApp(theme: ThemeData(extensions: [AppPalette.dark()]))`.
- Run tests with: `flutter test <path>`; static check with `flutter analyze`.
- Diff line content `TextStyle` is `fontSize: 12, fontFamily: 'monospace'` (unified/split) and `fontSize: 11, fontFamily: 'monospace'` (working-copy). Keep these unchanged.

---

## File Structure

- **Create** `lib/ui/common/diff_horizontal_scroll.dart` — the shared scroll wrapper. One job: make a child horizontally scrollable while filling the viewport when narrow.
- **Create** `test/ui/common/diff_horizontal_scroll_test.dart` — unit tests for the wrapper.
- **Modify** `lib/ui/common/diff_line_row.dart` — `DiffLineRow` content (drop `Expanded`/clip), `HunkLines` (wrap unified lines), `SplitHunkLines` + `_SplitCell` (fixed-width cells + wrap).
- **Create** `test/ui/common/hunk_lines_test.dart` — unified + side-by-side scroll behaviour.
- **Modify** `lib/ui/working_copy/hunk_row.dart` — `_HunkLineRow` content (drop `Expanded`/ellipsis), `HunkRow` (wrap line list).
- **Create** `test/ui/working_copy/hunk_row_test.dart` — working-copy scroll behaviour.

---

### Task 1: `DiffHorizontalScroll` shared widget

**Files:**
- Create: `lib/ui/common/diff_horizontal_scroll.dart`
- Test: `test/ui/common/diff_horizontal_scroll_test.dart`

**Interfaces:**
- Produces: `class DiffHorizontalScroll extends StatefulWidget` with `const DiffHorizontalScroll({required Widget child, Key? key})`. Renders a horizontal `Scrollbar` + `SingleChildScrollView` whose content has `minWidth` equal to the viewport width.

- [ ] **Step 1: Write the failing test**

Create `test/ui/common/diff_horizontal_scroll_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/common/diff_horizontal_scroll.dart';

Widget _host(Widget child, {double width = 300}) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, height: 200, child: child),
        ),
      ),
    );

void main() {
  testWidgets('scrolls horizontally when content exceeds the viewport',
      (tester) async {
    await tester.pumpWidget(
      _host(const DiffHorizontalScroll(child: SizedBox(width: 1000, height: 20))),
    );

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.axis, Axis.horizontal);
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
  });

  testWidgets('content narrower than the viewport does not scroll',
      (tester) async {
    await tester.pumpWidget(
      _host(const DiffHorizontalScroll(child: SizedBox(width: 50, height: 20))),
    );

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/common/diff_horizontal_scroll_test.dart`
Expected: FAIL — `Target of URI doesn't exist` / `DiffHorizontalScroll` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `lib/ui/common/diff_horizontal_scroll.dart`:

```dart
import 'package:flutter/material.dart';

/// Wraps a vertical stack of diff rows so long lines become reachable by
/// horizontal scrolling instead of being clipped.
///
/// The content is allowed to take its natural width; the [LayoutBuilder]
/// captures the viewport width and applies it as a `minWidth`, so the content
/// still fills the pane (and row backgrounds reach the right edge) when it is
/// narrower than the viewport.
class DiffHorizontalScroll extends StatefulWidget {
  const DiffHorizontalScroll({required this.child, super.key});

  final Widget child;

  @override
  State<DiffHorizontalScroll> createState() => _DiffHorizontalScrollState();
}

class _DiffHorizontalScrollState extends State<DiffHorizontalScroll> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Scrollbar(
          controller: _controller,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/common/diff_horizontal_scroll_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/common/diff_horizontal_scroll.dart test/ui/common/diff_horizontal_scroll_test.dart
git commit -m "feat: add DiffHorizontalScroll wrapper"
```

---

### Task 2: Unified diff lines scroll horizontally

**Files:**
- Modify: `lib/ui/common/diff_line_row.dart` (`DiffLineRow.build` content; `HunkLines.build` unified branch return)
- Test: `test/ui/common/hunk_lines_test.dart`

**Interfaces:**
- Consumes: `DiffHorizontalScroll` (Task 1).
- Produces: no API change. `HunkLines` in unified mode now renders its rows inside `DiffHorizontalScroll(IntrinsicWidth(Column(...)))`.

- [ ] **Step 1: Write the failing test**

Create `test/ui/common/hunk_lines_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/ui/common/diff_line_row.dart';
import 'package:gitopen/ui/common/diff_prefs.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

Widget _host(Widget child, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 300, height: 200, child: child),
          ),
        ),
      ),
    );

void main() {
  testWidgets('long unified line is horizontally scrollable', (tester) async {
    final lines = [
      DiffLine(kind: DiffLineKind.addition, content: 'x' * 400, newLine: 1),
    ];

    await tester.pumpWidget(_host(HunkLines(lines: lines)));

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.axis, Axis.horizontal);
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
  });

  testWidgets('long side-by-side line is horizontally scrollable',
      (tester) async {
    final lines = [
      DiffLine(kind: DiffLineKind.deletion, content: 'z' * 400, oldLine: 1),
      DiffLine(kind: DiffLineKind.addition, content: 'w' * 400, newLine: 1),
    ];

    await tester.pumpWidget(
      _host(
        HunkLines(lines: lines),
        overrides: [
          diffViewModeProvider.overrideWith((ref) => DiffViewMode.sideBySide),
        ],
      ),
    );

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
  });
}
```

> Note: the second test belongs to Task 4 (side-by-side). It is written here so the file is created once; expect it to FAIL until Task 4 is done. If running tasks strictly in isolation, comment it out and re-enable it in Task 4.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/common/hunk_lines_test.dart -n "long unified line is horizontally scrollable"`
Expected: FAIL — no horizontal `Scrollable` found / `maxScrollExtent` is 0 (lines are clipped, not scrollable).

- [ ] **Step 3: Write minimal implementation**

In `lib/ui/common/diff_line_row.dart`, add the import near the top (alongside the other `gitopen/ui/common` imports):

```dart
import 'package:gitopen/ui/common/diff_horizontal_scroll.dart';
```

Change the `DiffLineRow.build` content child — replace the `Expanded(child: Text.rich(...))` block (currently the last child of the `Row`) with a non-`Expanded`, non-clipped `Text.rich`:

```dart
          Text.rich(
            TextSpan(children: _contentSpans(palette)),
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            softWrap: false,
          ),
```

In `HunkLines.build`, replace the unified return (`return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [ for (final (i, line) in lines.indexed) DiffLineRow(...) ]);`) with:

```dart
    return DiffHorizontalScroll(
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, line) in lines.indexed)
              DiffLineRow(
                line: line,
                language: language,
                gutterWidth: gutterWidth,
                prefixWidth: prefixWidth,
                changedRange: ranges[i],
              ),
          ],
        ),
      ),
    );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/common/hunk_lines_test.dart -n "long unified line is horizontally scrollable"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/common/diff_line_row.dart test/ui/common/hunk_lines_test.dart
git commit -m "feat: horizontal scroll for unified diff lines"
```

---

### Task 3: Working-copy preview lines scroll horizontally

**Files:**
- Modify: `lib/ui/working_copy/hunk_row.dart` (`HunkRow.build` line list; `_HunkLineRow.build` content)
- Test: `test/ui/working_copy/hunk_row_test.dart`

**Interfaces:**
- Consumes: `DiffHorizontalScroll` (Task 1).
- Produces: no API change. `HunkRow` keeps its header fixed and wraps its `_HunkLineRow` list in `DiffHorizontalScroll`.

- [ ] **Step 1: Write the failing test**

Create `test/ui/working_copy/hunk_row_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/hunk_row.dart';

void main() {
  testWidgets('long working-copy line is horizontally scrollable',
      (tester) async {
    final hunk = DiffHunk(
      oldStart: 1,
      oldCount: 1,
      newStart: 1,
      newCount: 1,
      header: '@@ -1 +1 @@',
      lines: [
        DiffLine(kind: DiffLineKind.addition, content: 'y' * 400, newLine: 1),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 200,
              child: HunkRow(
                hunk: hunk,
                index: 0,
                staged: false,
                isChecked: false,
                onToggle: () {},
                selectedLines: const <int>{},
                onToggleLine: (_) {},
                onAction: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.axis, Axis.horizontal);
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/working_copy/hunk_row_test.dart`
Expected: FAIL — no horizontal `Scrollable` (line is ellipsized, not scrollable).

- [ ] **Step 3: Write minimal implementation**

In `lib/ui/working_copy/hunk_row.dart`, add the import:

```dart
import 'package:gitopen/ui/common/diff_horizontal_scroll.dart';
```

In `HunkRow.build`, the outer `Column`'s children are `[ Semantics(... header InkWell ...), for (final (lineIndex, line) in hunk.lines.indexed) _HunkLineRow(...) ]`. Replace the trailing `for (...) _HunkLineRow(...)` spread with a single wrapped child:

```dart
          DiffHorizontalScroll(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (lineIndex, line) in hunk.lines.indexed)
                    _HunkLineRow(
                      line: line,
                      isChecked: selectedLines.contains(lineIndex),
                      onToggle: () => onToggleLine(lineIndex),
                    ),
                ],
              ),
            ),
          ),
```

In `_HunkLineRow.build`, replace the content `Expanded(child: Text(line.content, overflow: TextOverflow.ellipsis, ...))` (the last child of the inner `Row`) with a non-`Expanded` text:

```dart
              Text(
                line.content,
                softWrap: false,
                style: TextStyle(
                  color: palette.fg1,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/working_copy/hunk_row_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/working_copy/hunk_row.dart test/ui/working_copy/hunk_row_test.dart
git commit -m "feat: horizontal scroll for working-copy diff preview"
```

---

### Task 4: Side-by-side lines scroll horizontally

**Files:**
- Modify: `lib/ui/common/diff_line_row.dart` (`SplitHunkLines.build` + `_SplitCell.build` content)
- Test: `test/ui/common/hunk_lines_test.dart` (re-enable the side-by-side test added in Task 2)

**Interfaces:**
- Consumes: `DiffHorizontalScroll` (Task 1), `buildSplitRows` / `SplitRow` (already imported in `diff_line_row.dart` from `application/diff/split_diff.dart`), `AppPalette`.
- Produces: no API change. Side-by-side rows use fixed-width cells (computed once per hunk) and the whole row column is wrapped in `DiffHorizontalScroll`.

- [ ] **Step 1: Confirm the failing test**

If the Task 2 side-by-side test was commented out, re-enable it now.

Run: `flutter test test/ui/common/hunk_lines_test.dart -n "long side-by-side line is horizontally scrollable"`
Expected: FAIL — `maxScrollExtent` is 0 (split cells are `Expanded`, so content is clipped to the viewport, not scrollable).

- [ ] **Step 2: Write minimal implementation**

In `lib/ui/common/diff_line_row.dart`, replace the body of `SplitHunkLines.build` with a precomputed-width, scrollable layout. Add a private side-width helper to the `SplitHunkLines` class:

```dart
  static const TextStyle _splitContentStyle = TextStyle(
    fontSize: 12,
    fontFamily: 'monospace',
  );

  // Widest rendered cell for one side, so the two columns line up across rows.
  double _sideWidth(List<SplitRow> rows, {required bool old}) {
    var maxChars = 0;
    for (final row in rows) {
      final line = old ? row.left : row.right;
      final length = line?.content.length ?? 0;
      if (length > maxChars) maxChars = length;
    }
    final painter = TextPainter(
      text: TextSpan(text: 'a' * maxChars, style: _splitContentStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final contentWidth = painter.width;
    painter.dispose();
    // gutter + 8px gap + content + 12px cell padding + 4px slack.
    return gutterWidth + 8 + contentWidth + 16;
  }

  @override
  Widget build(BuildContext context) {
    final rows = buildSplitRows(lines);
    final leftWidth = _sideWidth(rows, old: true);
    final rightWidth = _sideWidth(rows, old: false);
    final borderColor = AppPalette.of(context).border;
    return DiffHorizontalScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows)
            IntrinsicHeight(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: leftWidth,
                    child: _SplitCell(
                      line: row.left,
                      old: true,
                      language: language,
                      gutterWidth: gutterWidth,
                    ),
                  ),
                  Container(width: 1, color: borderColor),
                  SizedBox(
                    width: rightWidth,
                    child: _SplitCell(
                      line: row.right,
                      old: false,
                      language: language,
                      gutterWidth: gutterWidth,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
```

In `_SplitCell.build`, replace the content `Expanded(child: Text.rich(...))` (the last child of the inner `Row`) with a non-`Expanded` text:

```dart
          Text.rich(
            TextSpan(
              children: buildHighlightedSpans(
                l.content,
                language,
                baseColor: palette.fg0,
              ),
            ),
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            softWrap: false,
          ),
```

- [ ] **Step 3: Run test to verify it passes**

Run: `flutter test test/ui/common/hunk_lines_test.dart`
Expected: PASS (both unified and side-by-side tests).

- [ ] **Step 4: Commit**

```bash
git add lib/ui/common/diff_line_row.dart test/ui/common/hunk_lines_test.dart
git commit -m "feat: horizontal scroll for side-by-side diff"
```

---

### Task 5: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Run the full test suite**

Run: `flutter test`
Expected: PASS (all existing tests + the 3 new test files).

- [ ] **Step 2: Static analysis**

Run: `flutter analyze`
Expected: `No issues found!` (no new lint warnings from the changed files).

- [ ] **Step 3: Manual smoke check**

Run: `flutter run -d windows`
- Select a commit whose files have long lines → **Changes** tab → confirm a horizontal scrollbar appears under each hunk and long lines are fully reachable.
- Toggle **Split** (side-by-side) → confirm the hunk scrolls horizontally and the two columns stay aligned.
- Open **Local Changes**, expand a file with long lines → confirm the hunk preview scrolls horizontally and the hunk header + discard button stay fixed.
- Confirm short-line diffs look unchanged (no stray scrollbar; row backgrounds fill the pane).

- [ ] **Step 4: Commit (only if Steps 1-2 required fixes)**

```bash
git add -A
git commit -m "chore: fix analyze/test issues for diff horizontal scroll"
```

---

## Self-Review

**Spec coverage:**
- Render content at natural width → Tasks 2, 3, 4 (drop `Expanded`/clip in `DiffLineRow`, `_HunkLineRow`, `_SplitCell`). ✓
- Shared `DiffHorizontalScroll` with `LayoutBuilder` + `minWidth: viewport` → Task 1. ✓
- Per-hunk boundaries, headers fixed → Task 2 (HunkLines, hunk header in `_hunk` stays outside), Task 3 (HunkRow header stays fixed), Task 4 (SplitHunkLines). ✓
- Checkboxes scroll with content (working copy) → Task 3 wraps the `_HunkLineRow` list whole, including the fixed-left-padding checkbox column. ✓
- `IntrinsicWidth` perf note → bounded by capped diffs; no code action needed. ✓
- Side-by-side fixed-width cells via `TextPainter` → Task 4. ✓
- Tests: long line scrollable / short line not scrollable / per-view → Tasks 1-4 cover unified, working-copy, side-by-side, and the narrow/no-scroll case (Task 1). ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code. The cross-task note in Task 2 (side-by-side test created early) is explicit, not a placeholder.

**Type consistency:** `DiffHorizontalScroll({required Widget child})` used identically in Tasks 2-4. `DiffLine(kind:, content:, oldLine:, newLine:)`, `DiffHunk(oldStart:, oldCount:, newStart:, newCount:, header:, lines:)`, `SplitRow = ({DiffLine? left, DiffLine? right})`, `diffViewModeProvider`/`DiffViewMode.sideBySide`, `buildSplitRows`, `buildHighlightedSpans` all match the codebase signatures verified during planning.
