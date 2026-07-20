import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/working_copy/working_copy_providers.dart';

import '../../_helpers/diff_view_harness.dart';

void main() {
  test('file preview asks git only for the selected file', () async {
    final repo = testRepo();
    final fake = FakeDiffReadOps(
      diffOf([
        fileDiffFixture('first.dart'),
        fileDiffFixture('second.dart'),
      ]),
    );
    final container = ProviderContainer(
      overrides: [gitReadOperationsProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    final file = await container.read(
      unstagedFileDiffProvider((repo, 'second.dart')).future,
    );

    expect(file?.path, 'second.dart');
    expect(fake.getDiffForFileCalls, 1);
    expect(fake.getDiffCalls, 0);
  });
}
