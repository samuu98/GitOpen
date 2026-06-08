import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/commit_search_provider.dart';

void main() {
  group('CommitSearch.parse', () {
    test('empty / whitespace yields none', () {
      expect(CommitSearch.parse(''), CommitSearch.none);
      expect(CommitSearch.parse('   '), CommitSearch.none);
      expect(CommitSearch.parse('').isEmpty, isTrue);
    });

    test('bare words become a message grep', () {
      final s = CommitSearch.parse('fix login');
      expect(s.grep, 'fix login');
      expect(s.author, isNull);
      expect(s.touchingContent, isNull);
      expect(s.isEmpty, isFalse);
    });

    test('author: prefix sets author and is removed from grep', () {
      final s = CommitSearch.parse('author:alice');
      expect(s.author, 'alice');
      expect(s.grep, isNull);
    });

    test('touches: and content: prefixes set pickaxe content', () {
      expect(CommitSearch.parse('touches:token').touchingContent, 'token');
      expect(CommitSearch.parse('content:token').touchingContent, 'token');
    });

    test('field prefixes are case-insensitive', () {
      final s = CommitSearch.parse('Author:Bob');
      expect(s.author, 'Bob');
    });

    test('combines message grep with author filter', () {
      final s = CommitSearch.parse('session author:alice');
      expect(s.grep, 'session');
      expect(s.author, 'alice');
    });

    test('a colon with no value is treated as a plain message word', () {
      final s = CommitSearch.parse('author:');
      expect(s.author, isNull);
      expect(s.grep, 'author:');
    });

    test('value equality and hashCode', () {
      expect(
        CommitSearch.parse('fix author:bob'),
        CommitSearch.parse('fix author:bob'),
      );
      expect(
        CommitSearch.parse('fix author:bob').hashCode,
        CommitSearch.parse('fix author:bob').hashCode,
      );
      expect(
        CommitSearch.parse('fix'),
        isNot(CommitSearch.parse('other')),
      );
    });
  });
}
