import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/commit_request.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/settings/app_settings_notifier.dart';
import 'package:gitopen/application/settings/settings_store.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_commit_template_reader.dart';
import 'package:gitopen/infrastructure/git/git_identity_service.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/commit_compose.dart';

final class _Settings implements SettingsStore {
  @override
  Future<Map<String, dynamic>> readAll() async => {};

  @override
  Future<void> put(String key, dynamic value) async {}
}

final class _ConfigRunner extends GitProcessRunner {
  @override
  Future<String> run(
    String workingDir,
    List<String> args, {
    Duration? timeout,
  }) async => '';
}

final class _TemplateReader extends GitCliCommitTemplateReader {
  @override
  Future<String?> read(RepoLocation repo) async => 'Subject\n\nBody';
}

final class _Write implements GitWriteOperations {
  int commitCalls = 0;

  @override
  Future<GitResult<CommitSha>> commit(RepoLocation r, CommitRequest req) async {
    commitCalls++;
    return GitSuccess(CommitSha('abcdef1'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('prefills template and blocks unedited commit', (tester) async {
    try {
      final write = _Write();
      final repo = RepoLocation(RepoId.newId(), 'unused', 'test');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsProvider.overrideWith(
              (ref) => AppSettingsNotifier(_Settings()),
            ),
            gitCommitTemplateReaderProvider.overrideWithValue(
              _TemplateReader(),
            ),
            gitWriteOperationsProvider.overrideWithValue(write),
            gitIdentityServiceProvider.overrideWithValue(
              GitIdentityService(runner: _ConfigRunner()),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: [AppPalette.dark()]),
            home: Scaffold(body: CommitCompose(repo: repo, hasStaged: true)),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Subject\n\nBody',
      );
      await tester.tap(find.text('Commit'));
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CommitCompose)),
      );
      expect(
        container.read(operationsProvider).last.errorMessage,
        'Edit the commit template before committing.',
      );
      expect(write.commitCalls, 0);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
