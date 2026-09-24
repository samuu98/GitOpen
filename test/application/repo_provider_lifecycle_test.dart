import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/refs/tag.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/ui/commit_graph/commit_graph_providers.dart';

class _CountingRead implements GitReadOperations {
  int statusCalls = 0;
  int logCalls = 0;

  @override
  Future<RepoStatus> getStatus(RepoLocation repo) async {
    statusCalls++;
    return const RepoStatus(isDetached: false, isBare: false, entries: []);
  }

  @override
  Future<List<Branch>> getLocalBranches(RepoLocation repo) async => const [];
  @override
  Future<List<Branch>> getRemoteBranches(RepoLocation repo) async => const [];
  @override
  Stream<CommitInfo> getCommits(RepoLocation repo, CommitQuery query) {
    logCalls++;
    return const Stream.empty();
  }

  @override
  Future<List<Tag>> getTags(RepoLocation repo) async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

void main() {
  test('unwatched repo status and graph data reload after a switch', () async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
    final read = _CountingRead();
    final container = ProviderContainer(
      overrides: [
        gitReadOperationsProvider.overrideWithValue(read),
      ],
    );
    addTearDown(container.dispose);

    final status = container.listen(repoStatusProvider(repo), (_, _) {});
    final graph = container.listen(commitGraphDataProvider(repo), (_, _) {});
    await container.read(repoStatusProvider(repo).future);
    await container.read(commitGraphDataProvider(repo).future);
    expect(read.statusCalls, 1);
    expect(read.logCalls, 1);

    container.read(graphLimitProvider(repo).notifier).state = 600;
    await container.read(commitGraphDataProvider(repo).future);
    status.close();
    graph.close();
    await container.pump();

    final statusAgain = container.listen(repoStatusProvider(repo), (_, _) {});
    final graphAgain = container.listen(
      commitGraphDataProvider(repo),
      (_, _) {},
    );
    await container.read(repoStatusProvider(repo).future);
    await container.read(commitGraphDataProvider(repo).future);
    expect(read.statusCalls, 2);
    expect(read.logCalls, 3);
    expect(container.read(graphLimitProvider(repo)), 600);
    statusAgain.close();
    graphAgain.close();
  });
}
