import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/repo_revision.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

void main() {
  final repoA = RepoLocation(RepoId('a' * 32), '/tmp/a', 'A');
  final repoB = RepoLocation(RepoId('b' * 32), '/tmp/b', 'B');

  test('bumping one repo revision re-runs only that repo\'s reads', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    var runsA = 0;
    var runsB = 0;
    final read = FutureProvider.family<int, RepoLocation>((ref, repo) {
      ref.watch(repoRevisionProvider(repo));
      return repo == repoA ? ++runsA : ++runsB;
    });

    // Prime both and keep them alive so invalidation re-runs them.
    container.listen(read(repoA), (_, __) {});
    container.listen(read(repoB), (_, __) {});
    await container.read(read(repoA).future);
    await container.read(read(repoB).future);
    expect(runsA, 1);
    expect(runsB, 1);

    // Bump only repo A.
    container.read(repoRevisionProvider(repoA).notifier).state++;
    await container.read(read(repoA).future);
    await container.read(read(repoB).future);

    expect(runsA, 2, reason: "repo A read should re-run after its bump");
    expect(runsB, 1, reason: "repo B read must be untouched by A's bump");
  });
}
