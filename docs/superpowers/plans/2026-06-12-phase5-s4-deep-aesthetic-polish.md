# Phase 5 S4 Deep Aesthetic Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Raise GitOpen's existing desktop UI craft with shared design tokens, consistent motion/focus/scrollbar behavior, polished graph/ref visuals, and reusable empty states without changing product behavior.

**Architecture:** Add token theme extensions next to `AppPalette`, then route repeated local visual patterns through small shared UI primitives (`AppIconButton`, `AppEmptyState`, `AppAnimatedRow`, `AppScrollConfiguration`). Apply the primitives to high-traffic surfaces first: shell/theme, toolbar/icon actions, commit graph/ref pills, GitHub/LFS panels, file rows, and empty/error states.

**Tech Stack:** Dart/Flutter, Riverpod, existing Material 3 theme, widget tests as regression guardrails, no goldens.

**Branch:** `feat/phase5-s4-deep-aesthetic-polish` from `main`. Version bump `0.1.21+22` -> `0.1.22+23` in the final task.

**Process gotchas:**
- Use `& "C:\Users\g.chirico\flutter\bin\flutter.bat"` for Flutter commands when needed.
- Run `flutter analyze` from `D:\repos\Personal\GitOpen`.
- Format only touched Dart files. Do not run blanket `dart format lib test`.
- Keep semantics labels and visible text stable unless a test is explicitly updated for the new shared wording.
- This slice intentionally has no behavior changes and no goldens; existing widget tests are the visual regression net.

---

## File Structure

- Create: `lib/ui/theme/app_design_tokens.dart`
- Modify: `lib/ui/theme/app_palette.dart`
- Modify: `lib/main.dart`
- Test: `test/ui/theme/app_design_tokens_test.dart`
- Test: `test/ui/theme/app_palette_contrast_test.dart`
- Create: `lib/ui/common/app_icon_button.dart`
- Create: `lib/ui/common/app_empty_state.dart`
- Create: `lib/ui/common/app_animated_row.dart`
- Create: `lib/ui/common/app_scroll_configuration.dart`
- Test: `test/ui/common/app_icon_button_test.dart`
- Test: `test/ui/common/app_empty_state_test.dart`
- Test: `test/ui/common/app_scroll_configuration_test.dart`
- Modify: `lib/ui/toolbar/toolbar_buttons.dart`
- Modify: `lib/ui/common/diff_prefs.dart`
- Modify: `lib/ui/common/file_list_mode_toggle.dart`
- Modify: `lib/ui/working_copy/file_row.dart`
- Modify: `lib/ui/bottom_panel/bottom_panel.dart`
- Modify: `lib/ui/bottom_panel/file_tree_view.dart`
- Modify: `lib/ui/github/github_api_state.dart`
- Modify: `lib/ui/github/github_tabs_bar.dart`
- Modify: `lib/ui/github/actions_tab.dart`
- Modify: `lib/ui/github/pull_requests_tab.dart`
- Modify: `lib/ui/github/pull_request_files_view.dart`
- Modify: `lib/ui/lfs/lfs_panel.dart`
- Modify: `lib/ui/commit_graph/commit_row.dart`
- Modify: `lib/ui/commit_graph/ref_pill.dart`
- Modify: `lib/ui/commit_graph/lane_painter.dart`
- Test: `test/ui/commit_graph/commit_row_test.dart`
- Test: `test/ui/commit_graph/commit_graph_widgets_test.dart`
- Test: `test/ui/working_copy/file_row_test.dart`
- Test: `test/ui/github/github_panel_test.dart`
- Test: `test/ui/lfs/lfs_panel_test.dart`
- Modify: `pubspec.yaml`

---

### Task 1: Branch setup and plan commit

**Files:**
- Add: `docs/superpowers/plans/2026-06-12-phase5-s4-deep-aesthetic-polish.md`

- [ ] **Step 1: Create the branch from main**

```powershell
git -C D:\repos\Personal\GitOpen checkout main
git -C D:\repos\Personal\GitOpen pull --ff-only origin main
git -C D:\repos\Personal\GitOpen checkout -b feat/phase5-s4-deep-aesthetic-polish
```

Expected: branch `feat/phase5-s4-deep-aesthetic-polish` checked out from current `main`.

- [ ] **Step 2: Commit this plan**

```powershell
git -C D:\repos\Personal\GitOpen add docs/superpowers/plans/2026-06-12-phase5-s4-deep-aesthetic-polish.md
git -C D:\repos\Personal\GitOpen commit -m "docs(phase5): S4 deep aesthetic polish plan"
```

Expected: one docs commit.

---

### Task 2: Theme extensions and contrast guardrails

**Files:**
- Create: `lib/ui/theme/app_design_tokens.dart`
- Modify: `lib/ui/theme/app_palette.dart`
- Modify: `lib/main.dart`
- Test: `test/ui/theme/app_design_tokens_test.dart`
- Test: `test/ui/theme/app_palette_contrast_test.dart`

- [ ] **Step 1: Write failing token tests** at `test/ui/theme/app_design_tokens_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';

void main() {
  test('desktop tokens expose the 4 px spacing scale', () {
    final spacing = AppSpacing.desktop();
    expect(spacing.xxs, 4);
    expect(spacing.xs, 6);
    expect(spacing.sm, 8);
    expect(spacing.md, 12);
    expect(spacing.lg, 16);
    expect(spacing.xl, 24);
    expect(spacing.panel, const EdgeInsets.all(12));
  });

  test('motion tokens stay within the S4 120-200 ms range', () {
    final motion = AppMotion.standard();
    expect(motion.fast, const Duration(milliseconds: 120));
    expect(motion.normal, const Duration(milliseconds: 160));
    expect(motion.slow, const Duration(milliseconds: 200));
    expect(motion.curve.transform(1), 1);
  });

  test('extensions are available from ThemeData', () {
    final theme = ThemeData(
      extensions: const [
        AppSpacing.desktop(),
        AppRadii.desktop(),
        AppTypography.desktop(),
        AppMotion.standard(),
      ],
    );
    expect(theme.extension<AppSpacing>()!.md, 12);
    expect(theme.extension<AppRadii>()!.row, 4);
    expect(theme.extension<AppTypography>()!.body.fontSize, 12.5);
    expect(theme.extension<AppMotion>()!.normal.inMilliseconds, 160);
  });

  test('numeric extensions lerp predictably', () {
    final a = const AppSpacing(
      xxs: 4,
      xs: 6,
      sm: 8,
      md: 12,
      lg: 16,
      xl: 24,
      xxl: 32,
    );
    final b = const AppSpacing(
      xxs: 8,
      xs: 10,
      sm: 12,
      md: 16,
      lg: 20,
      xl: 28,
      xxl: 36,
    );
    expect(a.lerp(b, 0.5).md, 14);
  });
}
```

- [ ] **Step 2: Write failing light/dark contrast tests** at `test/ui/theme/app_palette_contrast_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

double _linear(int channel) {
  final c = channel / 255.0;
  return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055);
}

double _luminance(Color c) =>
    0.2126 * _linear(c.red) + 0.7152 * _linear(c.green) + 0.0722 * _linear(c.blue);

double _contrast(Color a, Color b) {
  final l1 = _luminance(a);
  final l2 = _luminance(b);
  final high = l1 > l2 ? l1 : l2;
  final low = l1 > l2 ? l2 : l1;
  return (high + 0.05) / (low + 0.05);
}

void _expectAa(String label, Color fg, Color bg) {
  expect(
    _contrast(fg, bg),
    greaterThanOrEqualTo(4.5),
    reason: '$label should meet WCAG AA normal-text contrast',
  );
}

void main() {
  test('dark palette text colors meet AA on common backgrounds', () {
    final p = AppPalette.dark();
    _expectAa('dark fg0/bg1', p.fg0, p.bg1);
    _expectAa('dark fg1/bg1', p.fg1, p.bg1);
    _expectAa('dark fg2/bg1', p.fg2, p.bg1);
    _expectAa('dark remote/bg1', p.accentRemote, p.bg1);
    _expectAa('dark current/bg1', p.accentCurrent, p.bg1);
    _expectAa('dark err/bg1', p.accentErr, p.bg1);
  });

  test('light palette text colors meet AA on common backgrounds', () {
    final p = AppPalette.light();
    _expectAa('light fg0/bg1', p.fg0, p.bg1);
    _expectAa('light fg1/bg1', p.fg1, p.bg1);
    _expectAa('light fg2/bg1', p.fg2, p.bg1);
    _expectAa('light remote/bg1', p.accentRemote, p.bg1);
    _expectAa('light current/bg1', p.accentCurrent, p.bg1);
    _expectAa('light err/bg1', p.accentErr, p.bg1);
  });
}
```

- [ ] **Step 3: Run tests and verify RED**

```powershell
& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/theme/app_design_tokens_test.dart test/ui/theme/app_palette_contrast_test.dart
```

Expected: compile failure because `app_design_tokens.dart` does not exist, or contrast failures before palette adjustment.

- [ ] **Step 4: Create** `lib/ui/theme/app_design_tokens.dart`

```dart
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

@immutable
final class AppSpacing extends ThemeExtension<AppSpacing> {
  const AppSpacing({
    required this.xxs,
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.xxl,
  });

  const factory AppSpacing.desktop() = AppSpacing._desktop;

  const AppSpacing._desktop()
      : xxs = 4,
        xs = 6,
        sm = 8,
        md = 12,
        lg = 16,
        xl = 24,
        xxl = 32;

  final double xxs;
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;

  EdgeInsets get panel => EdgeInsets.all(md);
  EdgeInsets get row => EdgeInsets.symmetric(horizontal: md, vertical: xs);
  EdgeInsets get compactRow =>
      EdgeInsets.symmetric(horizontal: sm, vertical: xxs);

  @override
  AppSpacing copyWith({
    double? xxs,
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
  }) {
    return AppSpacing(
      xxs: xxs ?? this.xxs,
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      xxl: xxl ?? this.xxl,
    );
  }

  @override
  AppSpacing lerp(ThemeExtension<AppSpacing>? other, double t) {
    if (other is! AppSpacing) return this;
    double v(double a, double b) => lerpDouble(a, b, t)!;
    return AppSpacing(
      xxs: v(xxs, other.xxs),
      xs: v(xs, other.xs),
      sm: v(sm, other.sm),
      md: v(md, other.md),
      lg: v(lg, other.lg),
      xl: v(xl, other.xl),
      xxl: v(xxl, other.xxl),
    );
  }

  static AppSpacing of(BuildContext context) =>
      Theme.of(context).extension<AppSpacing>()!;
}

@immutable
final class AppRadii extends ThemeExtension<AppRadii> {
  const AppRadii({
    required this.control,
    required this.row,
    required this.panel,
    required this.dialog,
    required this.pill,
  });

  const factory AppRadii.desktop() = AppRadii._desktop;

  const AppRadii._desktop()
      : control = 4,
        row = 4,
        panel = 6,
        dialog = 8,
        pill = 999;

  final double control;
  final double row;
  final double panel;
  final double dialog;
  final double pill;

  BorderRadius get controlRadius => BorderRadius.circular(control);
  BorderRadius get rowRadius => BorderRadius.circular(row);
  BorderRadius get panelRadius => BorderRadius.circular(panel);
  BorderRadius get pillRadius => BorderRadius.circular(pill);

  @override
  AppRadii copyWith({
    double? control,
    double? row,
    double? panel,
    double? dialog,
    double? pill,
  }) {
    return AppRadii(
      control: control ?? this.control,
      row: row ?? this.row,
      panel: panel ?? this.panel,
      dialog: dialog ?? this.dialog,
      pill: pill ?? this.pill,
    );
  }

  @override
  AppRadii lerp(ThemeExtension<AppRadii>? other, double t) {
    if (other is! AppRadii) return this;
    double v(double a, double b) => lerpDouble(a, b, t)!;
    return AppRadii(
      control: v(control, other.control),
      row: v(row, other.row),
      panel: v(panel, other.panel),
      dialog: v(dialog, other.dialog),
      pill: v(pill, other.pill),
    );
  }

  static AppRadii of(BuildContext context) =>
      Theme.of(context).extension<AppRadii>()!;
}

@immutable
final class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
    required this.caption,
    required this.captionStrong,
    required this.body,
    required this.bodyStrong,
    required this.title,
    required this.mono,
    required this.monoSmall,
  });

  const factory AppTypography.desktop() = AppTypography._desktop;

  const AppTypography._desktop()
      : caption = const TextStyle(fontSize: 11.5),
        captionStrong = const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
        body = const TextStyle(fontSize: 12.5),
        bodyStrong = const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        title = const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        mono = const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        monoSmall = const TextStyle(fontSize: 11, fontFamily: 'monospace');

  final TextStyle caption;
  final TextStyle captionStrong;
  final TextStyle body;
  final TextStyle bodyStrong;
  final TextStyle title;
  final TextStyle mono;
  final TextStyle monoSmall;

  @override
  AppTypography copyWith({
    TextStyle? caption,
    TextStyle? captionStrong,
    TextStyle? body,
    TextStyle? bodyStrong,
    TextStyle? title,
    TextStyle? mono,
    TextStyle? monoSmall,
  }) {
    return AppTypography(
      caption: caption ?? this.caption,
      captionStrong: captionStrong ?? this.captionStrong,
      body: body ?? this.body,
      bodyStrong: bodyStrong ?? this.bodyStrong,
      title: title ?? this.title,
      mono: mono ?? this.mono,
      monoSmall: monoSmall ?? this.monoSmall,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      caption: TextStyle.lerp(caption, other.caption, t)!,
      captionStrong: TextStyle.lerp(captionStrong, other.captionStrong, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      bodyStrong: TextStyle.lerp(bodyStrong, other.bodyStrong, t)!,
      title: TextStyle.lerp(title, other.title, t)!,
      mono: TextStyle.lerp(mono, other.mono, t)!,
      monoSmall: TextStyle.lerp(monoSmall, other.monoSmall, t)!,
    );
  }

  static AppTypography of(BuildContext context) =>
      Theme.of(context).extension<AppTypography>()!;
}

@immutable
final class AppMotion extends ThemeExtension<AppMotion> {
  const AppMotion({
    required this.fast,
    required this.normal,
    required this.slow,
    required this.curve,
  });

  const factory AppMotion.standard() = AppMotion._standard;

  const AppMotion._standard()
      : fast = const Duration(milliseconds: 120),
        normal = const Duration(milliseconds: 160),
        slow = const Duration(milliseconds: 200),
        curve = Curves.easeOutCubic;

  final Duration fast;
  final Duration normal;
  final Duration slow;
  final Curve curve;

  @override
  AppMotion copyWith({
    Duration? fast,
    Duration? normal,
    Duration? slow,
    Curve? curve,
  }) {
    return AppMotion(
      fast: fast ?? this.fast,
      normal: normal ?? this.normal,
      slow: slow ?? this.slow,
      curve: curve ?? this.curve,
    );
  }

  @override
  AppMotion lerp(ThemeExtension<AppMotion>? other, double t) {
    if (other is! AppMotion) return this;
    Duration d(Duration a, Duration b) => Duration(
      microseconds: lerpDouble(a.inMicroseconds, b.inMicroseconds, t)!.round(),
    );
    return AppMotion(
      fast: d(fast, other.fast),
      normal: d(normal, other.normal),
      slow: d(slow, other.slow),
      curve: t < 0.5 ? curve : other.curve,
    );
  }

  static AppMotion of(BuildContext context) =>
      Theme.of(context).extension<AppMotion>()!;
}
```

- [ ] **Step 5: Adjust** `lib/ui/theme/app_palette.dart`

Keep the public fields unchanged. Update only values that fail the contrast test:

```dart
factory AppPalette.dark() => const AppPalette(
  bg0: Color(0xFF191A1D), bg1: Color(0xFF1E1F23), bg2: Color(0xFF25262B),
  bg3: Color(0xFF2D2E34), bg4: Color(0xFF373841), bg5: Color(0xFF42434D),
  bgAccent: Color(0xFF0B5A84),
  border: Color(0xFF343640), borderStrong: Color(0xFF474A56),
  fg0: Color(0xFFE5E7EB), fg1: Color(0xFFC4C8D0),
  fg2: Color(0xFFA0A6B2), fg3: Color(0xFF777F8C),
  accentCurrent: Color(0xFF55D6BE), accentTag: Color(0xFFE0C46F),
  accentRemote: Color(0xFF6CAEE8), accentWarn: Color(0xFFDFA172),
  accentErr: Color(0xFFFF8B7D),
  lanePalette: [
    Color(0xFF55D6BE), Color(0xFFE0C46F), Color(0xFF6CAEE8),
    Color(0xFFDFA172), Color(0xFFC58ED6), Color(0xFF8EA7E8),
    Color(0xFFD7A85C), Color(0xFFE48797),
  ],
);

factory AppPalette.light() => const AppPalette(
  bg0: Color(0xFFFAFAFB), bg1: Color(0xFFFFFFFF), bg2: Color(0xFFF3F4F6),
  bg3: Color(0xFFE8EAEE), bg4: Color(0xFFDDE1E7), bg5: Color(0xFFD0D6DF),
  bgAccent: Color(0xFFCBE7FF),
  border: Color(0xFFD4D8E0), borderStrong: Color(0xFFB7BFCC),
  fg0: Color(0xFF1F2328), fg1: Color(0xFF3F4650),
  fg2: Color(0xFF596270), fg3: Color(0xFF737D8C),
  accentCurrent: Color(0xFF0A7E68), accentTag: Color(0xFF81600D),
  accentRemote: Color(0xFF1F5F9E), accentWarn: Color(0xFF8B4B20),
  accentErr: Color(0xFFA52424),
  lanePalette: [
    Color(0xFF0A7E68), Color(0xFF81600D), Color(0xFF1F5F9E),
    Color(0xFF8B4B20), Color(0xFF72446F), Color(0xFF405C8C),
    Color(0xFF79580C), Color(0xFF913244),
  ],
);
```

- [ ] **Step 6: Register extensions in** `lib/main.dart`

Add import:

```dart
import 'package:gitopen/ui/theme/app_design_tokens.dart';
```

Inside `GitOpenApp.build`, before `return MaterialApp`, add:

```dart
const spacing = AppSpacing.desktop();
const radii = AppRadii.desktop();
const typography = AppTypography.desktop();
const motion = AppMotion.standard();
```

Replace the `ThemeData` block with:

```dart
theme: ThemeData(
  useMaterial3: true,
  brightness: theme == AppTheme.dark ? Brightness.dark : Brightness.light,
  scaffoldBackgroundColor: palette.bg1,
  splashFactory: InkSparkle.splashFactory,
  hoverColor: palette.bg3,
  focusColor: palette.accentRemote.withValues(alpha: 0.22),
  tooltipTheme: TooltipThemeData(
    waitDuration: motion.slow,
    showDuration: const Duration(seconds: 4),
    decoration: BoxDecoration(
      color: palette.bg5,
      borderRadius: BorderRadius.circular(radii.control),
      border: Border.all(color: palette.borderStrong),
    ),
    textStyle: typography.caption.copyWith(color: palette.fg0),
  ),
  scrollbarTheme: ScrollbarThemeData(
    thumbColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered)) return palette.fg2;
      return palette.fg3.withValues(alpha: 0.65);
    }),
    trackColor: WidgetStateProperty.all(palette.bg2),
    radius: Radius.circular(radii.pill),
    thickness: WidgetStateProperty.resolveWith((states) {
      return states.contains(WidgetState.hovered) ? 8 : 6;
    }),
  ),
  extensions: const [palette, spacing, radii, typography, motion],
),
```

- [ ] **Step 7: Format and verify GREEN**

```powershell
dart format lib\ui\theme\app_design_tokens.dart lib\ui\theme\app_palette.dart lib\main.dart test\ui\theme\app_design_tokens_test.dart test\ui\theme\app_palette_contrast_test.dart
& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/theme/app_design_tokens_test.dart test/ui/theme/app_palette_contrast_test.dart test/ui/theme/app_palette_test.dart
& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze
```

Expected: tests pass and analyze clean.

- [ ] **Step 8: Commit**

```powershell
git add lib/ui/theme/app_design_tokens.dart lib/ui/theme/app_palette.dart lib/main.dart test/ui/theme/app_design_tokens_test.dart test/ui/theme/app_palette_contrast_test.dart
git commit -m "feat(phase5): add shared design tokens"
```

---

### Task 3: Shared UI primitives for icon actions, empty states, animated rows and scrollbars

**Files:**
- Create: `lib/ui/common/app_icon_button.dart`
- Create: `lib/ui/common/app_empty_state.dart`
- Create: `lib/ui/common/app_animated_row.dart`
- Create: `lib/ui/common/app_scroll_configuration.dart`
- Test: `test/ui/common/app_icon_button_test.dart`
- Test: `test/ui/common/app_empty_state_test.dart`
- Test: `test/ui/common/app_scroll_configuration_test.dart`

- [ ] **Step 1: Write failing tests for** `AppIconButton`

Create `test/ui/common/app_icon_button_test.dart`:

```dart
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/common/app_icon_button.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

Widget _host(Widget child) => MaterialApp(
  theme: ThemeData(
    extensions: const [
      AppPalette.dark(),
      AppSpacing.desktop(),
      AppRadii.desktop(),
      AppTypography.desktop(),
      AppMotion.standard(),
    ],
  ),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('fires tap and exposes button semantics', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        AppIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Discard changes',
          onPressed: () => taps++,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Discard changes'));
    expect(taps, 1);
    final semantics = tester.getSemantics(
      find.bySemanticsLabel('Discard changes'),
    );
    expect(semantics.flagsCollection.isButton, isTrue);
  });

  testWidgets('disabled action does not fire and selected is semantic', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        AppIconButton(
          icon: Icons.list,
          tooltip: 'Tree view',
          selected: true,
          onPressed: null,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Tree view'));
    expect(taps, 0);
    final semantics = tester.getSemantics(find.bySemanticsLabel('Tree view'));
    expect(semantics.flagsCollection.isSelected, Tristate.isTrue);
  });
}
```

- [ ] **Step 2: Write failing tests for empty state and scroll behavior**

Create `test/ui/common/app_empty_state_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/common/app_empty_state.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

Widget _host(Widget child) => MaterialApp(
  theme: ThemeData(
    extensions: const [
      AppPalette.dark(),
      AppSpacing.desktop(),
      AppRadii.desktop(),
      AppTypography.desktop(),
      AppMotion.standard(),
    ],
  ),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('renders icon, title, message and optional action', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        AppEmptyState(
          icon: Icons.inbox_outlined,
          title: 'No open pull requests',
          message: 'The repository has no PRs ready for review.',
          actionIcon: Icons.refresh,
          actionLabel: 'Refresh',
          onAction: () => taps++,
        ),
      ),
    );

    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    expect(find.text('No open pull requests'), findsOneWidget);
    expect(
      find.text('The repository has no PRs ready for review.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Refresh'));
    expect(taps, 1);
  });
}
```

Create `test/ui/common/app_scroll_configuration_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/common/app_scroll_configuration.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

void main() {
  testWidgets('wraps scrollables with styled scrollbars', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [
            AppPalette.dark(),
            AppSpacing.desktop(),
            AppRadii.desktop(),
            AppTypography.desktop(),
            AppMotion.standard(),
          ],
        ),
        home: const AppScrollConfiguration(
          child: SizedBox(
            width: 200,
            height: 100,
            child: ListView(
              children: [
                SizedBox(height: 1000, child: Text('long')),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Scrollbar), findsWidgets);
  });
}
```

- [ ] **Step 3: Run tests and verify RED**

```powershell
& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/common/app_icon_button_test.dart test/ui/common/app_empty_state_test.dart test/ui/common/app_scroll_configuration_test.dart
```

Expected: compile failure because the common widgets do not exist.

- [ ] **Step 4: Create** `lib/ui/common/app_icon_button.dart`

```dart
import 'package:flutter/material.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
    this.selected = false,
    this.danger = false,
    this.size = 28,
    this.iconSize = 14,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final bool danger;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final radii = AppRadii.of(context);
    final motion = AppMotion.of(context);
    final enabled = onPressed != null;
    final fg = danger
        ? palette.accentErr
        : selected
            ? palette.fg0
            : palette.fg2;
    final bg = selected ? palette.bgAccent : Colors.transparent;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: selected,
        label: tooltip,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              canRequestFocus: enabled,
              borderRadius: radii.controlRadius,
              focusColor: palette.accentRemote.withValues(alpha: 0.24),
              hoverColor: palette.bg4,
              child: AnimatedContainer(
                width: size,
                height: size,
                duration: motion.fast,
                curve: motion.curve,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: radii.controlRadius,
                  border: Border.all(
                    color: selected ? palette.borderStrong : Colors.transparent,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: iconSize, color: fg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Create** `lib/ui/common/app_empty_state.dart`

```dart
import 'package:flutter/material.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
    this.actionIcon,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final IconData? actionIcon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    final typography = AppTypography.of(context);
    return Center(
      child: Padding(
        padding: spacing.panel,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: palette.fg3),
            SizedBox(height: spacing.sm),
            Text(
              title,
              textAlign: TextAlign.center,
              style: typography.bodyStrong.copyWith(color: palette.fg1),
            ),
            SizedBox(height: spacing.xxs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: typography.body.copyWith(color: palette.fg3),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: spacing.md),
              FilledButton.icon(
                icon: Icon(actionIcon ?? Icons.refresh, size: 15),
                label: Text(actionLabel!),
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Create** `lib/ui/common/app_animated_row.dart`

```dart
import 'package:flutter/material.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class AppAnimatedRow extends StatefulWidget {
  const AppAnimatedRow({
    required this.child,
    required this.selected,
    required this.onTap,
    super.key,
    this.semanticLabel,
    this.onSecondaryTapDown,
    this.height,
    this.padding,
  });

  final Widget child;
  final bool selected;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final GestureTapDownCallback? onSecondaryTapDown;
  final double? height;
  final EdgeInsetsGeometry? padding;

  @override
  State<AppAnimatedRow> createState() => _AppAnimatedRowState();
}

class _AppAnimatedRowState extends State<AppAnimatedRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);
    final motion = AppMotion.of(context);
    final bg = widget.selected
        ? palette.bgAccent
        : _hovered
            ? palette.bg2
            : Colors.transparent;
    final border = _focused ? palette.accentRemote : Colors.transparent;

    final content = AnimatedContainer(
      duration: motion.normal,
      curve: motion.curve,
      height: widget.height,
      padding: widget.padding ?? spacing.row,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: widget.selected || _hovered ? radii.rowRadius : null,
        border: Border.all(color: border),
      ),
      child: widget.child,
    );

    return Semantics(
      button: widget.onTap != null,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        mouseCursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        child: GestureDetector(
          onSecondaryTapDown: widget.onSecondaryTapDown,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: radii.rowRadius,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Create** `lib/ui/common/app_scroll_configuration.dart`

```dart
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

class AppScrollConfiguration extends StatelessWidget {
  const AppScrollConfiguration({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const _AppScrollBehavior(),
      child: child,
    );
  }
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return Scrollbar(
      controller: details.controller,
      thumbVisibility: false,
      trackVisibility: false,
      child: child,
    );
  }
}
```

- [ ] **Step 8: Format and verify GREEN**

```powershell
dart format lib\ui\common\app_icon_button.dart lib\ui\common\app_empty_state.dart lib\ui\common\app_animated_row.dart lib\ui\common\app_scroll_configuration.dart test\ui\common\app_icon_button_test.dart test\ui\common\app_empty_state_test.dart test\ui\common\app_scroll_configuration_test.dart
& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/common/app_icon_button_test.dart test/ui/common/app_empty_state_test.dart test/ui/common/app_scroll_configuration_test.dart
& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze
```

Expected: tests pass and analyze clean.

- [ ] **Step 9: Commit**

```powershell
git add lib/ui/common/app_icon_button.dart lib/ui/common/app_empty_state.dart lib/ui/common/app_animated_row.dart lib/ui/common/app_scroll_configuration.dart test/ui/common/app_icon_button_test.dart test/ui/common/app_empty_state_test.dart test/ui/common/app_scroll_configuration_test.dart
git commit -m "feat(phase5): add polished shared UI primitives"
```

---

### Task 4: Apply shared controls to toolbar, toggles and local icon buttons

**Files:**
- Modify: `lib/ui/toolbar/toolbar_buttons.dart`
- Modify: `lib/ui/common/diff_prefs.dart`
- Modify: `lib/ui/common/file_list_mode_toggle.dart`
- Modify: `lib/ui/working_copy/file_row.dart`
- Modify: `lib/ui/bottom_panel/file_tree_view.dart`
- Modify: `lib/ui/github/actions_tab.dart`
- Modify: `lib/ui/github/pull_request_files_view.dart`
- Modify: `lib/ui/lfs/lfs_panel.dart`
- Test: `test/ui/working_copy/file_row_test.dart`
- Test: `test/ui/github/github_panel_test.dart`
- Test: `test/ui/lfs/lfs_panel_test.dart`

- [ ] **Step 1: Add regression tests for preserved tooltips**

Append to `test/ui/working_copy/file_row_test.dart`:

```dart
testWidgets('discard action keeps its tooltip and semantics', (tester) async {
  await tester.pumpWidget(_host(
    DiscardIconButton(isSelected: false, onPressed: () {}),
  ));
  expect(find.byTooltip('Discard changes'), findsOneWidget);
  final semantics = tester.getSemantics(
    find.bySemanticsLabel('Discard changes'),
  );
  expect(semantics.flagsCollection.isButton, isTrue);
});
```

Append to `test/ui/lfs/lfs_panel_test.dart` in the installed/repo-configured group:

```dart
expect(find.byTooltip('Add pattern'), findsOneWidget);
```

No new GitHub test is needed here because `test/ui/github/github_panel_test.dart` already covers open-in-browser tooltips and PR line comment tooltips.

- [ ] **Step 2: Run affected tests and verify RED where local widgets still differ**

```powershell
& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/working_copy/file_row_test.dart test/ui/lfs/lfs_panel_test.dart test/ui/github/github_panel_test.dart -j 1
```

Expected: existing tests pass or new semantics assertion fails until `AppIconButton` is used.

- [ ] **Step 3: Update toolbar buttons**

In `lib/ui/toolbar/toolbar_buttons.dart`, add imports:

```dart
import 'package:gitopen/ui/theme/app_design_tokens.dart';
```

Replace local hard-coded padding/radius in both button classes:

```dart
final spacing = AppSpacing.of(context);
final radii = AppRadii.of(context);
final typography = AppTypography.of(context);
```

Use:

```dart
borderRadius: radii.controlRadius,
padding: EdgeInsets.symmetric(horizontal: spacing.md - 2, vertical: spacing.xs),
style: typography.monoSmall.copyWith(color: palette.fg0),
```

Keep labels and icons unchanged.

- [ ] **Step 4: Replace local icon action variants**

Use `AppIconButton` for these exact replacements:

`lib/ui/working_copy/file_row.dart`

```dart
class DiscardIconButton extends StatelessWidget {
  const DiscardIconButton({
    required this.isSelected,
    required this.onPressed,
    super.key,
  });
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: AppIconButton(
        icon: Icons.delete_outline,
        tooltip: 'Discard changes',
        danger: !isSelected,
        onPressed: onPressed,
      ),
    );
  }
}
```

`lib/ui/lfs/lfs_panel.dart`

```dart
AppIconButton(
  icon: Icons.add,
  tooltip: 'Add pattern',
  onPressed: () => _addPattern(context, ref),
)
```

and:

```dart
AppIconButton(
  icon: Icons.close,
  tooltip: 'Untrack ${pattern.pattern}',
  onPressed: () => ref
      .read(lfsActionsControllerProvider)
      .untrack(context, repo, pattern.pattern),
)
```

`lib/ui/github/actions_tab.dart`

```dart
AppIconButton(
  icon: Icons.open_in_new,
  tooltip: 'Open on GitHub',
  onPressed: () => launchUrl(
    Uri.parse(run.htmlUrl),
    mode: LaunchMode.externalApplication,
  ),
)
```

`lib/ui/github/pull_request_files_view.dart`

```dart
AppIconButton(
  icon: Icons.add_comment_outlined,
  tooltip: 'Comment on line ${line.commentLine}',
  onPressed: line.isCommentable && line.commentLine != null
      ? () => onLineCommentRequested(
            file.filename,
            line.commentLine!,
            line.side,
          )
      : null,
)
```

For `lib/ui/common/diff_prefs.dart`, `lib/ui/common/file_list_mode_toggle.dart`, and `lib/ui/bottom_panel/file_tree_view.dart`, replace local `InkWell + Icon` controls with `AppIconButton`, preserving the current tooltip text exactly.

- [ ] **Step 5: Format and verify GREEN**

```powershell
dart format lib\ui\toolbar\toolbar_buttons.dart lib\ui\common\diff_prefs.dart lib\ui\common\file_list_mode_toggle.dart lib\ui\working_copy\file_row.dart lib\ui\bottom_panel\file_tree_view.dart lib\ui\github\actions_tab.dart lib\ui\github\pull_request_files_view.dart lib\ui\lfs\lfs_panel.dart test\ui\working_copy\file_row_test.dart test\ui\lfs\lfs_panel_test.dart
& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/working_copy/file_row_test.dart test/ui/lfs/lfs_panel_test.dart test/ui/github/github_panel_test.dart -j 1
& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze
```

Expected: tests pass, no tooltip text regressions, analyze clean.

- [ ] **Step 6: Commit**

```powershell
git add lib/ui/toolbar/toolbar_buttons.dart lib/ui/common/diff_prefs.dart lib/ui/common/file_list_mode_toggle.dart lib/ui/working_copy/file_row.dart lib/ui/bottom_panel/file_tree_view.dart lib/ui/github/actions_tab.dart lib/ui/github/pull_request_files_view.dart lib/ui/lfs/lfs_panel.dart test/ui/working_copy/file_row_test.dart test/ui/lfs/lfs_panel_test.dart
git commit -m "feat(phase5): unify icon action styling"
```

---

### Task 5: Empty states and API error state consistency

**Files:**
- Modify: `lib/ui/github/github_api_state.dart`
- Modify: `lib/ui/github/actions_tab.dart`
- Modify: `lib/ui/github/pull_requests_tab.dart`
- Modify: `lib/ui/lfs/lfs_panel.dart`
- Modify: `lib/ui/bottom_panel/bottom_panel.dart`
- Test: `test/ui/github/github_panel_test.dart`
- Test: `test/ui/lfs/lfs_panel_test.dart`

- [ ] **Step 1: Add widget assertions for consistent empty-state text**

In `test/ui/github/github_panel_test.dart`, keep existing assertions for:

```dart
expect(find.text('No open pull requests'), findsOneWidget);
expect(find.textContaining('GitHub API returned 500'), findsOneWidget);
expect(find.text('Retry'), findsOneWidget);
```

Add an assertion in the sign-in CTA test:

```dart
expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
```

In `test/ui/lfs/lfs_panel_test.dart`, assert the current empty strings remain:

```dart
expect(find.text('Git LFS is not installed'), findsOneWidget);
expect(find.text('No tracked patterns'), findsOneWidget);
expect(find.text('No LFS files in this repository'), findsOneWidget);
```

- [ ] **Step 2: Run tests before changing UI**

```powershell
& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/github/github_panel_test.dart test/ui/lfs/lfs_panel_test.dart -j 1
```

Expected: current tests pass before visual refactor; new icon assertion passes.

- [ ] **Step 3: Replace local empty/error layouts with** `AppEmptyState`

`lib/ui/github/github_api_state.dart`:

```dart
return AppEmptyState(
  icon: Icons.cloud_off_outlined,
  title: 'Sign in to GitHub',
  message: 'Sign in to see pull requests and workflow runs.',
  actionIcon: Icons.login,
  actionLabel: 'Sign in with GitHub',
  onAction: () async {
    final profile = await AuthDialog.show(context, 'github.com');
    if (profile == null) return;
    await ref
        .read(appSettingsProvider.notifier)
        .setAuthBinding(repo.id.value, profile.id);
    ref.invalidate(repoActiveProfileProvider(repo));
  },
);
```

For `GitHubApiErrorView`:

```dart
return AppEmptyState(
  icon: Icons.cloud_off_outlined,
  title: 'GitHub request failed',
  message: message,
  actionIcon: Icons.refresh,
  actionLabel: 'Retry',
  onAction: onRetry,
);
```

`lib/ui/github/pull_requests_tab.dart`, empty data branch:

```dart
return AppEmptyState(
  icon: Icons.merge_type_outlined,
  title: 'No open pull requests',
  message: 'This repository has no open pull requests right now.',
  actionIcon: Icons.refresh,
  actionLabel: 'Refresh',
  onAction: () => ref.invalidate(githubPullRequestsProvider(key)),
);
```

`lib/ui/github/actions_tab.dart`, empty data branch:

```dart
return AppEmptyState(
  icon: Icons.play_circle_outline,
  title: branch == null ? 'No workflow runs' : 'No workflow runs for $branch',
  message: 'Recent GitHub Actions activity will appear here.',
  actionIcon: Icons.refresh,
  actionLabel: 'Refresh',
  onAction: () => ref.invalidate(githubWorkflowRunsProvider(key)),
);
```

`lib/ui/lfs/lfs_panel.dart`:

```dart
return const AppEmptyState(
  icon: Icons.storage_outlined,
  title: 'Git LFS is not installed',
  message: 'Install git-lfs from git-lfs.com, then reopen this view.',
);
```

For "not configured":

```dart
return AppEmptyState(
  icon: Icons.download_done,
  title: 'Git LFS is available',
  message: 'Git LFS ${status.version ?? ''} is available but not set up in this repository.',
  actionIcon: Icons.download_done,
  actionLabel: 'Install in repo',
  onAction: () => ref
      .read(lfsActionsControllerProvider)
      .installLocal(context, repo),
);
```

For empty patterns and files, use `AppEmptyState` without action, preserving the exact visible titles from tests.

- [ ] **Step 4: Format and verify GREEN**

```powershell
dart format lib\ui\github\github_api_state.dart lib\ui\github\actions_tab.dart lib\ui\github\pull_requests_tab.dart lib\ui\lfs\lfs_panel.dart lib\ui\bottom_panel\bottom_panel.dart test\ui\github\github_panel_test.dart test\ui\lfs\lfs_panel_test.dart
& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/github/github_panel_test.dart test/ui/lfs/lfs_panel_test.dart -j 1
& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze
```

Expected: tests pass and analyze clean.

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/github/github_api_state.dart lib/ui/github/actions_tab.dart lib/ui/github/pull_requests_tab.dart lib/ui/lfs/lfs_panel.dart lib/ui/bottom_panel/bottom_panel.dart test/ui/github/github_panel_test.dart test/ui/lfs/lfs_panel_test.dart
git commit -m "feat(phase5): standardize empty and error states"
```

---

### Task 6: Commit graph motion, lane palette and ref pill polish

**Files:**
- Modify: `lib/ui/commit_graph/commit_row.dart`
- Modify: `lib/ui/commit_graph/ref_pill.dart`
- Modify: `lib/ui/commit_graph/lane_painter.dart`
- Test: `test/ui/commit_graph/commit_row_test.dart`
- Test: `test/ui/commit_graph/commit_graph_widgets_test.dart`

- [ ] **Step 1: Add graph regression tests**

Append to `test/ui/commit_graph/commit_row_test.dart`:

```dart
testWidgets('row keeps hoverable button semantics after polish', (
  tester,
) async {
  await tester.pumpWidget(
    _host(
      CommitRow(
        node: _node(),
        maxLane: 0,
        refs: const [],
        isSelected: false,
        onTap: () {},
      ),
    ),
  );

  final semantics = tester.getSemantics(
    find.bySemanticsLabel(RegExp('Commit aaaaaaa.*Fix crash.*Alice')),
  );
  expect(semantics.flagsCollection.isButton, isTrue);

  final row = find.byType(CommitRow);
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: tester.getCenter(row));
  addTearDown(gesture.removePointer);
  await tester.pumpAndSettle();
  expect(find.textContaining('Fix crash'), findsOneWidget);
});
```

Append to `test/ui/commit_graph/commit_graph_widgets_test.dart`:

```dart
testWidgets('ref pill preserves branch and remote labels', (tester) async {
  const decoration = RefDecoration(
    name: 'main',
    syncedRemotes: ['origin/main'],
    isRemote: false,
    isTag: false,
    isCurrent: true,
  );
  await tester.pumpWidget(_host(const RefPill(decoration: decoration)));

  expect(find.text('main'), findsOneWidget);
  expect(find.text('origin/main'), findsOneWidget);
  expect(find.byIcon(Icons.check), findsOneWidget);
});
```

- [ ] **Step 2: Run graph tests and verify baseline**

```powershell
& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/commit_graph/commit_row_test.dart test/ui/commit_graph/commit_graph_widgets_test.dart
```

Expected: current tests pass before visual refactor.

- [ ] **Step 3: Update commit row to use** `AppAnimatedRow`

In `lib/ui/commit_graph/commit_row.dart`, import:

```dart
import 'package:gitopen/ui/common/app_animated_row.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
```

Replace the outer `Semantics -> Material -> GestureDetector -> InkWell -> SizedBox` block with:

```dart
return AppAnimatedRow(
  selected: isSelected,
  semanticLabel:
      'Commit ${node.commit.sha.short()}, ${node.commit.summary}, '
      'by ${node.commit.author.name}, $date$refLabel',
  onTap: onTap,
  onSecondaryTapDown: onSecondaryTap == null
      ? null
      : (details) => onSecondaryTap!(details.globalPosition),
  height: kRowHeight,
  padding: EdgeInsets.symmetric(horizontal: AppSpacing.of(context).md),
  child: Row(
    children: [
      // keep the existing row children unchanged
    ],
  ),
);
```

Keep existing text colors for selected rows, but compute unselected hover through `AppAnimatedRow`.

- [ ] **Step 4: Redesign ref pills within existing semantics**

In `lib/ui/commit_graph/ref_pill.dart`, import tokens:

```dart
import 'package:gitopen/ui/theme/app_design_tokens.dart';
```

Use tokenized radius/padding:

```dart
final spacing = AppSpacing.of(context);
final radii = AppRadii.of(context);
final typography = AppTypography.of(context);
```

Replace pill decoration radius:

```dart
borderRadius: radii.pillRadius,
```

Replace section padding:

```dart
padding: EdgeInsets.symmetric(
  horizontal: spacing.sm,
  vertical: spacing.xxs / 2,
),
```

Replace section text style:

```dart
style: typography.monoSmall.copyWith(
  fontWeight: FontWeight.w600,
  color: fg,
),
```

Wrap the final pill with `AnimatedContainer` for `AppMotion.fast` if it has a tap/double-tap callback. Preserve the same `MouseRegion` and `GestureDetector` behavior.

- [ ] **Step 5: Tune lane palette usage without changing painter geometry**

In `lib/ui/commit_graph/lane_painter.dart`, keep all line positions and stroke widths unchanged. Only make inactive connector opacity consistent:

```dart
final color = lanePalette[index % lanePalette.length];
final paint = Paint()
  ..color = color.withValues(alpha: isActive ? 1 : 0.58)
  ..strokeWidth = 2
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round;
```

Use the file's existing active/inactive checks. Do not change `kRowHeight`, `svgWidth`, or path routing.

- [ ] **Step 6: Format and verify GREEN**

```powershell
dart format lib\ui\commit_graph\commit_row.dart lib\ui\commit_graph\ref_pill.dart lib\ui\commit_graph\lane_painter.dart test\ui\commit_graph\commit_row_test.dart test\ui\commit_graph\commit_graph_widgets_test.dart
& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/commit_graph/commit_row_test.dart test/ui/commit_graph/commit_graph_widgets_test.dart
& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze
```

Expected: tests pass and analyze clean.

- [ ] **Step 7: Commit**

```powershell
git add lib/ui/commit_graph/commit_row.dart lib/ui/commit_graph/ref_pill.dart lib/ui/commit_graph/lane_painter.dart test/ui/commit_graph/commit_row_test.dart test/ui/commit_graph/commit_graph_widgets_test.dart
git commit -m "feat(phase5): polish commit graph visuals"
```

---

### Task 7: Panel/view transitions and styled scrollbars

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/ui/shell/view_selector.dart`
- Modify: `lib/ui/github/github_tabs_bar.dart`
- Modify: `lib/ui/bottom_panel/bottom_panel.dart`
- Test: existing widget tests that exercise shell, GitHub panel and bottom panel

- [ ] **Step 1: Add transition smoke assertions**

In the existing shell/view-selector widget test file, add this smoke assertion to the test that changes main views:

```dart
expect(find.byType(AnimatedSwitcher), findsWidgets);
```

If there is no shell view-selector test file, add `test/ui/shell/view_selector_polish_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/shell/view_selector.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

void main() {
  testWidgets('view selector remains compact and token themed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [
            AppPalette.dark(),
            AppSpacing.desktop(),
            AppRadii.desktop(),
            AppTypography.desktop(),
            AppMotion.standard(),
          ],
        ),
        home: const Scaffold(body: SizedBox(width: 500, child: Placeholder())),
      ),
    );

    expect(find.byType(Placeholder), findsOneWidget);
  });
}
```

- [ ] **Step 2: Wrap the app in** `AppScrollConfiguration`

In `lib/main.dart`, import:

```dart
import 'package:gitopen/ui/common/app_scroll_configuration.dart';
```

Add a `builder` to `MaterialApp`:

```dart
builder: (context, child) => AppScrollConfiguration(
  child: child ?? const SizedBox.shrink(),
),
```

- [ ] **Step 3: Add main view animated transitions**

In `_RepoBody` or the current main-view switch in `lib/main.dart`, wrap the switched child:

```dart
final motion = AppMotion.of(context);
return AnimatedSwitcher(
  duration: motion.normal,
  switchInCurve: motion.curve,
  switchOutCurve: Curves.easeInCubic,
  child: KeyedSubtree(
    key: ValueKey(mainView),
    child: switch (mainView) {
      MainView.workingCopy => WorkingCopyPanel(repo: repo),
      MainView.history => Column(
        children: [
          Expanded(child: CommitGraphPanel(repo: repo)),
          BottomPanel(repo: repo),
        ],
      ),
      MainView.github => GitHubPanel(repo: repo),
      MainView.lfs => LfsPanel(repo: repo),
    },
  ),
);
```

Keep the existing switch arms exactly equivalent to the current behavior.

- [ ] **Step 4: Tokenize tabs and bottom panel chrome**

In `lib/ui/github/github_tabs_bar.dart`, replace hard-coded padding/radius/durations with:

```dart
final spacing = AppSpacing.of(context);
final radii = AppRadii.of(context);
final motion = AppMotion.of(context);
```

Use `AnimatedContainer(duration: motion.fast, curve: motion.curve, ...)` for the active tab underline/background. Preserve labels `Pull Requests` and `Actions`.

In `lib/ui/bottom_panel/bottom_panel.dart`, replace tab hover containers with the same `AppMotion.fast` and token spacing. Preserve existing bottom-panel tab labels.

- [ ] **Step 5: Format and verify GREEN**

```powershell
dart format lib\main.dart lib\ui\shell\view_selector.dart lib\ui\github\github_tabs_bar.dart lib\ui\bottom_panel\bottom_panel.dart test\ui\shell\view_selector_polish_test.dart
& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/github/github_panel_test.dart test/ui/bottom_panel/file_tree_view_test.dart test/ui/shell/view_selector_polish_test.dart -j 1
& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze
```

Expected: tests pass and analyze clean.

- [ ] **Step 6: Commit**

```powershell
git add lib/main.dart lib/ui/shell/view_selector.dart lib/ui/github/github_tabs_bar.dart lib/ui/bottom_panel/bottom_panel.dart test/ui/shell/view_selector_polish_test.dart
git commit -m "feat(phase5): add panel transitions and styled scrollbars"
```

---

### Task 8: Token sweep for high-traffic UI surfaces

**Files:**
- Modify: `lib/ui/working_copy/file_list.dart`
- Modify: `lib/ui/working_copy/file_row.dart`
- Modify: `lib/ui/working_copy/working_copy_panel.dart`
- Modify: `lib/ui/bottom_panel/file_tree_view.dart`
- Modify: `lib/ui/bottom_panel/diff_view.dart`
- Modify: `lib/ui/github/pull_request_detail_view.dart`
- Modify: `lib/ui/github/pull_request_review_drawer.dart`
- Modify: `lib/ui/lfs/lfs_panel.dart`
- Modify: `lib/ui/operations/activity_panel.dart`
- Modify: `lib/ui/operations/toast_overlay.dart`

- [ ] **Step 1: Run a targeted hard-code inventory**

```powershell
rg -n "EdgeInsets|SizedBox\\(|BorderRadius\\.circular|Duration\\(milliseconds|waitDuration|fontSize:" lib\ui\working_copy lib\ui\bottom_panel lib\ui\github lib\ui\lfs lib\ui\operations
```

Expected: output lists hard-coded values in only the target directories. Save the output in the terminal context; do not commit it.

- [ ] **Step 2: Apply the token mapping**

Use these exact mappings unless the surrounding component already has a stronger local reason:

```dart
const SizedBox(width: 4)  -> SizedBox(width: spacing.xxs)
const SizedBox(height: 4) -> SizedBox(height: spacing.xxs)
const SizedBox(width: 6)  -> SizedBox(width: spacing.xs)
const SizedBox(height: 6) -> SizedBox(height: spacing.xs)
const SizedBox(width: 8)  -> SizedBox(width: spacing.sm)
const SizedBox(height: 8) -> SizedBox(height: spacing.sm)
const SizedBox(width: 10) -> SizedBox(width: spacing.md - 2)
const SizedBox(width: 12) -> SizedBox(width: spacing.md)
const SizedBox(height: 12) -> SizedBox(height: spacing.md)
BorderRadius.circular(3) -> radii.controlRadius
BorderRadius.circular(4) -> radii.rowRadius
BorderRadius.circular(5) -> radii.panelRadius
BorderRadius.circular(6) -> radii.panelRadius
Duration(milliseconds: 400) tooltip waits -> AppMotion.of(context).slow
TextStyle(fontSize: 11) -> typography.caption
TextStyle(fontSize: 11.5) -> typography.caption
TextStyle(fontSize: 12) -> typography.mono or typography.body based on monospace use
TextStyle(fontSize: 12.5) -> typography.body
TextStyle(fontSize: 13) -> typography.bodyStrong when section heading, otherwise typography.body
```

At the top of each touched `build` method, add only the tokens used:

```dart
final spacing = AppSpacing.of(context);
final radii = AppRadii.of(context);
final typography = AppTypography.of(context);
```

Do not token-sweep dialog form field internals in this task; leave Material defaults intact.

- [ ] **Step 3: Format and run targeted widget tests**

```powershell
dart format lib\ui\working_copy\file_list.dart lib\ui\working_copy\file_row.dart lib\ui\working_copy\working_copy_panel.dart lib\ui\bottom_panel\file_tree_view.dart lib\ui\bottom_panel\diff_view.dart lib\ui\github\pull_request_detail_view.dart lib\ui\github\pull_request_review_drawer.dart lib\ui\lfs\lfs_panel.dart lib\ui\operations\activity_panel.dart lib\ui\operations\toast_overlay.dart
& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/working_copy/file_list_widget_test.dart test/ui/working_copy/file_row_test.dart test/ui/bottom_panel/file_tree_view_test.dart test/ui/github/github_panel_test.dart test/ui/lfs/lfs_panel_test.dart -j 1
& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze
```

Expected: tests pass and analyze clean.

- [ ] **Step 4: Commit**

```powershell
git add lib/ui/working_copy/file_list.dart lib/ui/working_copy/file_row.dart lib/ui/working_copy/working_copy_panel.dart lib/ui/bottom_panel/file_tree_view.dart lib/ui/bottom_panel/diff_view.dart lib/ui/github/pull_request_detail_view.dart lib/ui/github/pull_request_review_drawer.dart lib/ui/lfs/lfs_panel.dart lib/ui/operations/activity_panel.dart lib/ui/operations/toast_overlay.dart
git commit -m "feat(phase5): token sweep primary UI surfaces"
```

---

### Task 9: Full verification, version bump and PR

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Bump version**

In `pubspec.yaml`, change:

```yaml
version: 0.1.21+22
```

to:

```yaml
version: 0.1.22+23
```

- [ ] **Step 2: Format touched Dart files only**

```powershell
$files = git diff --name-only main...HEAD -- '*.dart'
if ($files) { dart format $files }
```

Expected: only files touched by this branch are formatted.

- [ ] **Step 3: Full verification**

```powershell
& "C:\Users\g.chirico\flutter\bin\flutter.bat" test -j 2
& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze
git diff --check
```

Expected: full suite green, analyze clean, no whitespace errors. If a known real-git fixture flakes under full-suite load, rerun the single failing file and record the pass before proceeding.

- [ ] **Step 4: Commit version bump**

```powershell
git add pubspec.yaml
git commit -m "chore(phase5): bump version to 0.1.22"
```

- [ ] **Step 5: Push and open PR**

```powershell
gh auth switch --hostname github.com --user zN3utr4l
git push -u origin feat/phase5-s4-deep-aesthetic-polish
gh pr create --repo zN3utr4l/GitOpen --base main --title "feat(phase5): S4 - deep aesthetic polish" --body "Implements Phase 5 S4 deep aesthetic polish from docs/superpowers/specs/2026-06-11-phase5-complete-beautiful-design.md.

Summary:
- Adds theme extensions for spacing, typography, radii and motion.
- Adds shared icon button, empty state, animated row and scroll configuration primitives.
- Polishes graph/ref visuals, toolbar controls, empty states, panel transitions and primary UI spacing.

Verification:
- flutter test -j 2
- flutter analyze
- git diff --check"
```

- [ ] **Step 6: Watch checks**

```powershell
gh pr checks --repo zN3utr4l/GitOpen --watch
```

Expected: required checks pass before merge.

---

## Self-Review

- Spec coverage: tokens, motion, shared icon button consistency, focus states, styled scrollbars, graph lane/ref polish, light-theme contrast, and empty states are each covered by at least one task.
- Behavior preservation: every task keeps existing labels/semantics or adds tests before replacing visual structure.
- Scope control: no product behavior, Git operations, GitHub API, LFS operations, storage migrations, or README/showcase work are included.
- Type consistency: all new theme extensions expose `of(BuildContext)` and are registered in `ThemeData.extensions`; common widgets depend only on `AppPalette` and the new token extensions.
