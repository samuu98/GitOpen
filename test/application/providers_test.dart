import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/providers.dart';

void main() {
  test('all providers resolve in a fresh ProviderContainer', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(gitProcessRunnerProvider), isNotNull);
    expect(c.read(gitReadOperationsProvider), isNotNull);
    // The DB-touching providers should resolve without throwing too —
    // they don't actually open the SQLite file until first query.
    expect(c.read(repositoryRegistryProvider), isNotNull);
    expect(c.read(workspacePersistenceProvider), isNotNull);
  });
}
