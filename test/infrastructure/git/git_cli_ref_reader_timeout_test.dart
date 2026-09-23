import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_ref_reader.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';

class _TimeoutRunner extends GitProcessRunner {
  Duration? requestedTimeout;
  bool killed = false;

  @override
  Future<String> run(
    String workingDir,
    List<String> args, {
    Duration? timeout,
  }) async {
    requestedTimeout = timeout;
    if (timeout == null) throw StateError('runner timeout missing');
    killed = true;
    throw GitProcessException(args, -1, 'timed out');
  }
}

void main() {
  test(
    'divergence passes timeout to killing runner and returns empty',
    () async {
      final runner = _TimeoutRunner();
      final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');

      final divergence = await GitCliRefReader(
        runner,
      ).localBranchDivergence(repo);

      expect(runner.requestedTimeout, const Duration(seconds: 3));
      expect(runner.killed, isTrue);
      expect(divergence, isEmpty);
    },
  );
}
