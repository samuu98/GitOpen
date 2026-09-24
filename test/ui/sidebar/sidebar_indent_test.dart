import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/refs/remote.dart';
import 'package:gitopen/domain/refs/tag.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/sidebar/remotes_section.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/sidebar/tag_row.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: ThemeData(extensions: [AppPalette.dark()]),
    home: Scaffold(body: SizedBox(width: 360, height: 320, child: child)),
  ),
);

void main() {
  group('sidebar indentation hierarchy', () {
    test('section/chevron column never deeper than the row column', () {
      // A parent (section header chevron) must not be more indented than the
      // content beneath it — the exact regression being guarded.
      expect(kSidebarChevronIndent, lessThanOrEqualTo(kSidebarRowIndent));
    });

    testWidgets('a remote group aligns its chevron with the section column', (
      tester,
    ) async {
      final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
      const remote = Remote(
        name: 'origin',
        url: 'https://github.com/o/r.git',
        branches: <Branch>[],
      );
      await tester.pumpWidget(
        _host(RemoteGroup(remote: remote, repo: repo, onChanged: () {})),
      );
      await tester.pump();

      // The "origin" row's left padding is the row glyph column — one step
      // inside the REMOTES header, NOT level with it and not further left
      // (it had regressed to 6px, left of the section header at 14px).
      expect(
        tester.getTopLeft(find.byIcon(Icons.expand_more).first).dx,
        kSidebarRowGlyphIndent,
      );
    });

    testWidgets('a flat row sits at the shared row column', (tester) async {
      final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
      final tag = Tag(
        name: 'v1.0.0',
        fullName: 'refs/tags/v1.0.0',
        targetSha: CommitSha('aaaaaaaa'),
        isAnnotated: false,
      );
      await tester.pumpWidget(
        _host(TagRow(tag: tag, repo: repo, onRefresh: () {})),
      );
      await tester.pump();

      // Empty hints ("No tags") share this same constant, so locking it here
      // keeps the hint aligned with real rows.
      expect(
        tester.getTopLeft(find.text('v1.0.0')).dx,
        kSidebarRowIndent,
      );
    });

    // Flat rows and empty hints have no leading glyph, so putting their text
    // in the glyph column left them sticking out ~18px to the left of every
    // other label in the panel — "No submodules" was the visible symptom.
    test('flat rows label in the same column as chevron-led rows', () {
      expect(
        kSidebarRowIndent,
        kSidebarLabelIndent,
        reason:
            'a glyph-less row must start where a glyph-led row label '
            'starts, not where its glyph starts',
      );
      expect(
        kSidebarLabelIndent,
        kSidebarRowGlyphIndent + kSidebarGlyphColumnWidth + kSidebarGlyphGap,
      );
      // Section content nests inside its header rather than sitting level
      // with it.
      expect(kSidebarRowGlyphIndent, greaterThan(kSidebarChevronIndent));
    });
  });
}
