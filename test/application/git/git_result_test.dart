import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';

void main() {
  group('GitResult', () {
    test('GitSuccess holds value', () {
      const r = GitSuccess<int>(42);
      expect(r.value, 42);
    });

    test('GitFailure has kind and message', () {
      const r = GitFailure<int>(GitErrorKind.auth, 'bad token', 'fatal: 401');
      expect(r.kind, GitErrorKind.auth);
      expect(r.message, 'bad token');
      expect(r.rawOutput, 'fatal: 401');
    });

    test('switch is exhaustive', () {
      const GitResult<String> r = GitSuccess<String>('ok');
      final out = switch (r) {
        GitSuccess(value: final v) => v,
        GitFailure() => 'err',
      };
      expect(out, 'ok');
    });
  });
}
