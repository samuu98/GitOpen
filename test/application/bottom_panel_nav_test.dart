import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/active_workspace_provider.dart';

void main() {
  test('bottom-panel tab defaults to commit; reveal path defaults to null', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(bottomPanelTabProvider), 'commit');
    expect(c.read(revealFilePathProvider), isNull);
  });
}
