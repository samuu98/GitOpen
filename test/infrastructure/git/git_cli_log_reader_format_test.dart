import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/infrastructure/git/git_cli_log_reader.dart';

void main() {
  group('commitLogFormat', () {
    test('omits %G? when signatures are not verified', () {
      // %G? forces git to GPG-verify every commit, which costs seconds on a
      // history with signed commits whose public keys are not available
      // locally. The commit graph never displays signature status, so its log
      // must not request verification.
      final fmt = commitLogFormat(verifySignature: false);
      expect(fmt, isNot(contains('%G?')));
      // The field count must match the number of `%x00`-separated
      // placeholders (git's format uses the literal token `%x00` for NUL).
      expect(
        '%x00'.allMatches(fmt).length + 1,
        commitLogFieldCount(verifySignature: false),
      );
    });

    test('appends %G? as the last field when signatures are verified', () {
      final fmt = commitLogFormat(verifySignature: true);
      expect(fmt, endsWith('%G?'));
      expect(
        '%x00'.allMatches(fmt).length + 1,
        commitLogFieldCount(verifySignature: true),
      );
    });

    test('verification adds exactly one trailing field', () {
      expect(
        commitLogFieldCount(verifySignature: true),
        commitLogFieldCount(verifySignature: false) + 1,
      );
    });
  });
}
