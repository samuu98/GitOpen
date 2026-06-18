import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/infrastructure/git/ahead_behind.dart';

void main() {
  test('parses ahead+behind, single sides, gone, empty', () {
    expect(parseAheadBehind('[ahead 2, behind 3]'), (ahead: 2, behind: 3));
    expect(parseAheadBehind('[ahead 2]'), (ahead: 2, behind: 0));
    expect(parseAheadBehind('[behind 1]'), (ahead: 0, behind: 1));
    expect(parseAheadBehind('[gone]'), (ahead: 0, behind: 0));
    expect(parseAheadBehind(''), (ahead: 0, behind: 0));
  });
}
