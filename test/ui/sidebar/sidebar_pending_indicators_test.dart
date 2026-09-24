import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/refs/stash.dart';
import 'package:gitopen/domain/refs/tag.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_interactive_surface.dart';
import 'package:gitopen/ui/sidebar/stash_row.dart';
import 'package:gitopen/ui/sidebar/tag_row.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

void main() {
  testWidgets(
    'tag and stash rows disable navigation while their own action is pending',
    (tester) async {
      final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData(
              extensions: [
                AppPalette.dark(),
                const AppSpacing.desktop(),
                const AppRadii.desktop(),
                const AppTypography.desktop(),
              ],
            ),
            home: Scaffold(
              body: SizedBox(
                width: 400,
                child: Column(
                  children: [
                    TagRow(
                      tag: Tag(
                        name: 'v1',
                        fullName: 'refs/tags/v1',
                        targetSha: CommitSha('aaaa'),
                        isAnnotated: false,
                      ),
                      repo: repo,
                      onRefresh: () {},
                    ),
                    StashRow(
                      stash: Stash(
                        index: 0,
                        sha: CommitSha('bbbb'),
                        message: 'work',
                        createdAt: DateTime.utc(2026),
                      ),
                      repo: repo,
                      onRefresh: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      container
          .read(busyProvider.notifier)
          .begin('${repo.id.value}/tag-delete:v1');
      container
          .read(busyProvider.notifier)
          .begin('${repo.id.value}/stash-drop:0');
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
      final surfaces = tester
          .widgetList<AppInteractiveSurface>(find.byType(AppInteractiveSurface))
          .toList();
      expect(surfaces.every((surface) => surface.onTap == null), isTrue);
      container
          .read(busyProvider.notifier)
          .end('${repo.id.value}/tag-delete:v1');
      container
          .read(busyProvider.notifier)
          .end('${repo.id.value}/stash-drop:0');
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
}
