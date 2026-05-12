import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/infrastructure/git/git_progress_parser.dart';

void main() {
  group('GitProgressParser', () {
    test('parses Counting line', () {
      final p = GitProgressParser.parse('Counting objects:  45% (180/400)');
      expect(p, isNotNull);
      expect(p!.phase, 'Counting objects');
      expect(p.fraction, closeTo(0.45, 0.001));
    });

    test('parses remote: Receiving', () {
      final p = GitProgressParser.parse('remote: Receiving objects:  23% (92/400)');
      expect(p!.phase, 'Receiving objects');
      expect(p.fraction, closeTo(0.23, 0.001));
    });

    test('returns null for non-progress lines', () {
      expect(GitProgressParser.parse('fatal: not a git repository'), isNull);
      expect(GitProgressParser.parse(''), isNull);
    });
  });
}
