import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/operations/busy_notifier.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/refs/tag.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/sidebar/tag_row.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

final _tag = Tag(
  name: 'v1.2.3',
  fullName: 'refs/tags/v1.2.3',
  targetSha: CommitSha('b' * 40),
  isAnnotated: true,
);

const _repo = RepoLocation(RepoId('tags'), 'unused', 't');

class _Read implements GitReadOperations {
  @override
  Future<RepoStatus> getStatus(RepoLocation repo) async =>
      const RepoStatus(isDetached: false, isBare: false, entries: []);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _Controller implements GitActionsController {
  final List<String> checkouts = [];

  @override
  Future<ActionResult> checkout(RepoLocation repo, String ref) async {
    checkouts.add(ref);
    return const ActionResult(ActionOutcome.success);
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

/// Ahem-font menu rows overflow by a few pixels in tests only; swallow
/// exactly that error (see branch_tree_view_test.dart).
void ignoreMenuOverflow() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed by')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

Widget _row() => MaterialApp(
  theme: ThemeData(extensions: [AppPalette.dark()]),
  home: Scaffold(
    body: TagRow(tag: _tag, repo: _repo),
  ),
);

Widget _host() => ProviderScope(child: _row());

void main() {
  testWidgets('renders the tag name', (tester) async {
    await tester.pumpWidget(_host());
    expect(find.text('v1.2.3'), findsOneWidget);
  });

  testWidgets('context menu offers Checkout / Push tag / Delete tag', (
    tester,
  ) async {
    ignoreMenuOverflow();
    await tester.pumpWidget(_host());
    await tester.tap(find.text('v1.2.3'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Checkout'), findsOneWidget);
    expect(find.text('Push tag'), findsOneWidget);
    expect(find.text('Delete tag'), findsOneWidget);
  });

  testWidgets('double click checks the tag out once', (tester) async {
    final controller = _Controller();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: _container(controller),
        child: _row(),
      ),
    );
    await _doubleTap(tester);
    await tester.pumpAndSettle();
    expect(controller.checkouts, ['v1.2.3']);
  });

  testWidgets('double click is ignored while an action runs', (tester) async {
    for (final key in [
      '${_repo.id.value}/tag-delete:${_tag.name}',
      '${_repo.id.value}/push-tag:${_tag.name}',
      '${_repo.id.value}/checkout:other',
    ]) {
      final controller = _Controller();
      final container = _container(controller, running: key);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: _row()),
      );
      await _doubleTap(tester);
      expect(controller.checkouts, isEmpty, reason: 'blocked by $key');
      container.read(busyProvider.notifier).end(key);
      await tester.pump();
    }
  });
}

ProviderContainer _container(_Controller controller, {String? running}) {
  final container = ProviderContainer(
    overrides: [
      gitReadOperationsProvider.overrideWithValue(_Read()),
      gitActionsControllerProvider.overrideWithValue(controller),
      if (running != null)
        // Never-visible indicator: the test only needs the action to count as
        // running, without an animation `pumpAndSettle` could never settle.
        busyProvider.overrideWith(
          (ref) => BusyNotifier(
            showDelay: const Duration(days: 1),
            minVisible: Duration.zero,
          )..begin(running),
        ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _doubleTap(WidgetTester tester) async {
  await tester.tap(find.text('v1.2.3'), warnIfMissed: false);
  await tester.pump(kDoubleTapMinTime);
  await tester.tap(find.text('v1.2.3'), warnIfMissed: false);
  await tester.pump();
}
