import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/git/repo_state_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/workspaces/repository_registry.dart';
import 'package:gitopen/application/workspaces/repository_validator.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/ui/common/app_interactive_surface.dart';
import 'package:gitopen/ui/status_bar/status_bar.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

void main() {
  testWidgets(
    'status bar path, activity and account have hover, focus and tooltips',
    (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          repositoryRegistryProvider.overrideWithValue(_Registry()),
          repositoryValidatorProvider.overrideWithValue(const _Validator()),
          branchesProvider.overrideWith((ref, repo) async => []),
          repoStatusProvider.overrideWith(
            (ref, repo) async =>
                const RepoStatus(isDetached: false, isBare: false, entries: []),
          ),
          repoStateProvider.overrideWith(
            (ref, repo) async => InProgressOp.none,
          ),
          repoActiveProfileProvider.overrideWith((ref, repo) async => null),
        ],
      );
      addTearDown(container.dispose);
      await container.read(workspaceManagerProvider.notifier).loadAll();
      container.read(activeWorkspaceIdProvider.notifier).state = const RepoId(
        'repo',
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData(extensions: [AppPalette.dark()]),
            home: const Scaffold(body: StatusBar()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Copy repository path'), findsOneWidget);
      expect(find.byTooltip('View activity'), findsOneWidget);
      expect(find.byTooltip('Switch account'), findsOneWidget);
      final path = find.widgetWithText(AppInteractiveSurface, 'C:/repo');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(path));
      await tester.pump();
      final hovered = tester.widget<AnimatedContainer>(
        find.descendant(of: path, matching: find.byType(AnimatedContainer)),
      );
      expect(
        (hovered.decoration! as BoxDecoration).color,
        AppPalette.dark().interactionHover,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final focused = tester.widget<AnimatedContainer>(
        find.descendant(of: path, matching: find.byType(AnimatedContainer)),
      );
      expect(
        (focused.decoration! as BoxDecoration).border!.top.color,
        AppPalette.dark().interactionFocusRing,
      );
      expect(find.byType(AppInteractiveSurface), findsNWidgets(3));
      await mouse.removePointer();
    },
  );
}

final class _Registry implements RepositoryRegistry {
  @override
  Future<List<RepoLocation>> list() async => [
    const RepoLocation(RepoId('repo'), 'C:/repo', 'repo'),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

final class _Validator implements RepositoryValidator {
  const _Validator();
  @override
  Future<String> validate(String path) async => path;
}
