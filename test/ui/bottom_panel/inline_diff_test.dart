import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/bottom_panel/inline_diff.dart';

void main() {
  String changedText(List<InlineSegment> segs) =>
      segs.where((s) => s.changed).map((s) => s.text).join();
  String allText(List<InlineSegment> segs) => segs.map((s) => s.text).join();

  test('identical lines have no changed segments', () {
    final (oldSegs, newSegs) = computeInlineDiff('hello world', 'hello world');
    expect(oldSegs.any((s) => s.changed), isFalse);
    expect(newSegs.any((s) => s.changed), isFalse);
  });

  test('isolates the single changed word', () {
    final (oldSegs, newSegs) =
        computeInlineDiff('final int count = 0;', 'final int total = 0;');
    expect(changedText(oldSegs), 'count');
    expect(changedText(newSegs), 'total');
    // The rest is preserved verbatim.
    expect(allText(oldSegs), 'final int count = 0;');
    expect(allText(newSegs), 'final int total = 0;');
  });

  test('pure addition marks only the appended tokens', () {
    final (oldSegs, newSegs) = computeInlineDiff('a b', 'a b c');
    expect(oldSegs.any((s) => s.changed), isFalse);
    expect(changedText(newSegs).trim(), 'c');
  });

  test('round-trips the full text on both sides', () {
    const a = 'the quick brown fox';
    const b = 'the slow brown dog';
    final (oldSegs, newSegs) = computeInlineDiff(a, b);
    expect(allText(oldSegs), a);
    expect(allText(newSegs), b);
  });
}
