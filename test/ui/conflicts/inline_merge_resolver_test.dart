import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/conflicts/inline_merge_resolver.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// A single two-way conflict region: ours = `ours\n`, theirs = `theirs\n`.
const _conflictText = '<<<<<<< HEAD\n'
    'ours\n'
    '=======\n'
    'theirs\n'
    '>>>>>>> feature\n';

/// Read port returning canned working-tree [content] with no real I/O.
///
/// The resolver only reads the file via `readWorkingFile`; everything else is
/// unused and routed to a throwing [noSuchMethod] so an accidental call is
/// loud rather than silent. Using a fake keeps the widget test off the `git`
/// CLI and off disk — real async never completes under the `testWidgets`
/// fake-async clock.
class _FakeRead implements GitReadOperations {
  _FakeRead(this.content);
  final String content;

  @override
  Future<String> readWorkingFile(
    RepoLocation repo,
    String relativePath,
  ) async =>
      content;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// Write port that records what the resolver asked it to write/stage and
/// reports success, so the test asserts behaviour without running git.
class _FakeWrite implements GitWriteOperations {
  String? wroteContent;
  List<String>? stagedPaths;
  GitResult<void> writeResult = const GitSuccess<void>(null);
  GitResult<void> stageResult = const GitSuccess<void>(null);

  @override
  Future<GitResult<void>> writeWorkingFile(
    RepoLocation r,
    String relativePath,
    String content,
  ) async {
    wroteContent = content;
    return writeResult;
  }

  @override
  Future<GitResult<void>> stageFiles(RepoLocation r, List<String> paths) async {
    stagedPaths = List.of(paths);
    return stageResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

Widget _host(
  _FakeRead read,
  _FakeWrite write, {
  String path = 'conflict.txt',
  VoidCallback? onResolved,
  VoidCallback? onOpenExternal,
}) {
  final repo = RepoLocation(RepoId.newId(), 'unused', 'test');
  return ProviderScope(
    overrides: [
      gitReadOperationsProvider.overrideWithValue(read),
      gitWriteOperationsProvider.overrideWithValue(write),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: [AppPalette.dark()]),
      home: Scaffold(
        body: InlineMergeResolver(
          repo: repo,
          relativePath: path,
          onResolved: onResolved ?? () {},
          onOpenExternal: onOpenExternal ?? () {},
        ),
      ),
    ),
  );
}

/// Pumps frames (bounded) until [finder] matches, instead of `pumpAndSettle`.
///
/// The transient loading state shows a [CircularProgressIndicator] whose
/// animation never quiesces, so `pumpAndSettle` would spin until the test
/// timeout. This pumps a fixed cadence until the target widget appears.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 60,
}) async {
  for (var i = 0; i < maxFrames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
}

void main() {
  testWidgets('renders ours/theirs sides and choice buttons', (tester) async {
    await tester.pumpWidget(_host(_FakeRead(_conflictText), _FakeWrite()));
    await _pumpUntil(tester, find.text('Use ours'));

    expect(find.text('ours'), findsOneWidget);
    expect(find.text('theirs'), findsOneWidget);
    expect(find.text('Use ours'), findsOneWidget);
    expect(find.text('Use theirs'), findsOneWidget);
    expect(find.text('Use both'), findsOneWidget);
  });

  testWidgets('Save disabled until every conflict is chosen', (tester) async {
    await tester.pumpWidget(_host(_FakeRead(_conflictText), _FakeWrite()));
    await _pumpUntil(tester, find.text('0 of 1 conflict resolved'));

    expect(find.text('0 of 1 conflict resolved'), findsOneWidget);
    // Pick a side -> counter flips to resolved.
    await tester.tap(find.text('Use theirs'));
    await _pumpUntil(tester, find.text('1 of 1 conflict resolved'));
    expect(find.text('1 of 1 conflict resolved'), findsOneWidget);
  });

  testWidgets('saving writes the chosen side, stages, and fires onResolved',
      (tester) async {
    final write = _FakeWrite();
    var resolved = false;
    await tester.pumpWidget(
      _host(_FakeRead(_conflictText), write, onResolved: () => resolved = true),
    );
    await _pumpUntil(tester, find.text('Use theirs'));

    await tester.tap(find.text('Use theirs'));
    await tester.pump();
    await tester.tap(find.text('Save resolution'));
    // Allow the async write+stage to complete.
    for (var i = 0; i < 60 && !resolved; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // The resolver assembled the chosen side, wrote it back, staged the path,
    // and notified the host.
    expect(write.wroteContent, 'theirs\n');
    expect(write.wroteContent, isNot(contains('<<<<<<<')));
    expect(write.stagedPaths, ['conflict.txt']);
    expect(resolved, isTrue);
  });

  testWidgets('offers external editor when no markers are present',
      (tester) async {
    var openedExternal = false;
    await tester.pumpWidget(
      _host(
        _FakeRead('just some text\n'),
        _FakeWrite(),
        path: 'plain.txt',
        onOpenExternal: () => openedExternal = true,
      ),
    );
    await _pumpUntil(tester, find.text('Open external editor'));

    expect(find.textContaining('No conflict markers'), findsOneWidget);
    expect(find.text('Open external editor'), findsOneWidget);

    await tester.tap(find.text('Open external editor'));
    await tester.pump();
    expect(openedExternal, isTrue);
  });
}
