import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/ui/commit_graph/commit_graph_providers.dart';

void main() {
  test('graph timeout cancels the git log stream', () async {
    var cancelled = false;
    final controller = StreamController<CommitInfo>(
      onCancel: () => cancelled = true,
    );

    await expectLater(
      collectGraphCommits(controller.stream, const Duration(milliseconds: 20)),
      throwsA(isA<TimeoutException>()),
    );
    expect(cancelled, isTrue);
    await controller.close();
  });
}
