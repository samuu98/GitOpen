import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/diff/intraline_diff.dart';

void main() {
  group('intralineDiff', () {
    test('isolates a changed word between common prefix and suffix', () {
      final d = intralineDiff('final count = 1;', 'final count = 2;')!;
      expect(d.oldStart, 14);
      expect(d.oldEnd, 15);
      expect(d.newStart, 14);
      expect(d.newEnd, 15);
    });

    test('insertion in the middle yields an empty old range', () {
      final d = intralineDiff('ab', 'aXb')!;
      expect(d.oldStart, 1);
      expect(d.oldEnd, 1); // nothing removed
      expect(d.newStart, 1);
      expect(d.newEnd, 2); // 'X'
    });

    test('identical lines yield null (nothing to highlight)', () {
      expect(intralineDiff('same', 'same'), isNull);
    });

    test('completely different lines highlight everything', () {
      final d = intralineDiff('aaa', 'zzzz')!;
      expect(d.oldStart, 0);
      expect(d.oldEnd, 3);
      expect(d.newStart, 0);
      expect(d.newEnd, 4);
    });

    test('prefix and suffix never overlap on repeated content', () {
      // old: 'aa', new: 'aaa' — naive prefix(2) + suffix(2) would overlap.
      final d = intralineDiff('aa', 'aaa')!;
      expect(d.oldStart, lessThanOrEqualTo(d.oldEnd));
      expect(d.newStart, lessThanOrEqualTo(d.newEnd));
      expect(d.oldEnd, lessThanOrEqualTo(2));
      expect(d.newEnd, lessThanOrEqualTo(3));
    });
  });

  group('pairChangedLines', () {
    test('pairs k-th deletion with k-th addition inside a run', () {
      // - a1   - a2   + b1   + b2  → (0,2) and (1,3)
      final pairs = pairChangedLines([
        (kind: PairKind.deletion, index: 0),
        (kind: PairKind.deletion, index: 1),
        (kind: PairKind.addition, index: 2),
        (kind: PairKind.addition, index: 3),
        (kind: PairKind.context, index: 4),
      ]);
      expect(pairs, {0: 2, 2: 0, 1: 3, 3: 1});
    });

    test('unbalanced runs leave the extra lines unpaired', () {
      final pairs = pairChangedLines([
        (kind: PairKind.deletion, index: 0),
        (kind: PairKind.addition, index: 1),
        (kind: PairKind.addition, index: 2),
      ]);
      expect(pairs, {0: 1, 1: 0});
    });

    test('context lines split pairing runs', () {
      final pairs = pairChangedLines([
        (kind: PairKind.deletion, index: 0),
        (kind: PairKind.context, index: 1),
        (kind: PairKind.addition, index: 2),
      ]);
      expect(pairs, isEmpty);
    });
  });
}
