import 'package:gitopen/application/git_lfs/git_lfs_models.dart';

String? parseGitLfsVersion(String raw) {
  final match = RegExp(r'git-lfs/([^\s]+)').firstMatch(raw.trim());
  return match?.group(1);
}

/// Parses `.gitattributes` content, keeping only the LFS rules — the file
/// can also carry unrelated attributes (eol, diff drivers) that must not
/// show up as tracked patterns.
List<GitLfsTrackedPattern> parseGitLfsTrackList(String raw) {
  return raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && line.contains('filter=lfs'))
      .map((line) {
        final parts = line.split(RegExp(r'\s+'));
        return GitLfsTrackedPattern(
          pattern: parts.first,
          attributes: parts.skip(1).join(' '),
          source: '.gitattributes',
        );
      })
      .toList(growable: false);
}

List<GitLfsFile> parseGitLfsLsFiles(String raw) {
  final re = RegExp(r'^([0-9a-fA-F]+)\s+[-*]\s+(.+?)\s+\(([^)]+)\)$');
  return raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map((line) {
        final match = re.firstMatch(line);
        if (match == null) {
          return GitLfsFile(oid: '', path: line, sizeLabel: '');
        }
        return GitLfsFile(
          oid: match.group(1)!,
          path: match.group(2)!,
          sizeLabel: match.group(3)!,
        );
      })
      .toList(growable: false);
}
