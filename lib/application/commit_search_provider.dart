import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Parsed commit-graph search terms.
///
/// The raw search text is parsed into independent filters so the graph can
/// pass them to `git log`.  Supported syntax (all optional, space-separated):
///   * `author:<value>`  — filter by author name/email
///   * `touches:<value>`  (alias `content:<value>`) — pickaxe content search
///   * any remaining bare words — matched against the commit message (grep)
///
/// When [isEmpty], the graph behaves exactly as if no search were active.
@immutable
class CommitSearch {
  const CommitSearch({this.grep, this.author, this.touchingContent});

  /// Parses a raw search string into a [CommitSearch].
  ///
  /// Leading/trailing whitespace is ignored.  Field prefixes are
  /// case-insensitive (`Author:foo` == `author:foo`).  Everything not claimed
  /// by a recognised prefix is concatenated back into the message grep so a
  /// plain query like `fix login` searches messages for `fix login`.
  factory CommitSearch.parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return none;

    String? author;
    String? touchingContent;
    final messageWords = <String>[];

    for (final token in trimmed.split(RegExp(r'\s+'))) {
      final colon = token.indexOf(':');
      if (colon > 0) {
        final field = token.substring(0, colon).toLowerCase();
        final value = token.substring(colon + 1);
        if (value.isNotEmpty) {
          switch (field) {
            case 'author':
              author = value;
              continue;
            case 'touches':
            case 'content':
              touchingContent = value;
              continue;
          }
        }
      }
      messageWords.add(token);
    }

    final grep = messageWords.isEmpty ? null : messageWords.join(' ');
    return CommitSearch(
      grep: grep,
      author: author,
      touchingContent: touchingContent,
    );
  }

  /// The "no search" value — every field null.
  static const none = CommitSearch();

  final String? grep;
  final String? author;
  final String? touchingContent;

  bool get isEmpty =>
      grep == null && author == null && touchingContent == null;

  @override
  bool operator ==(Object other) =>
      other is CommitSearch &&
      other.grep == grep &&
      other.author == author &&
      other.touchingContent == touchingContent;

  @override
  int get hashCode => Object.hash(grep, author, touchingContent);
}

/// Holds the active commit-graph search terms.  Defaults to [CommitSearch.none]
/// so the graph renders identically to the pre-search behaviour until the user
/// types something.
final commitSearchProvider =
    StateProvider<CommitSearch>((_) => CommitSearch.none);
