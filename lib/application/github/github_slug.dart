import 'package:gitopen/application/github/github_models.dart';

final RegExp _https =
    RegExp(r'^https?://github\.com/([^/]+)/([^/]+?)(\.git)?/?$');
final RegExp _ssh = RegExp(r'^git@github\.com:([^/]+)/([^/]+?)(\.git)?$');

/// Extracts the `owner/repo` slug from a github.com remote URL (https or
/// ssh), or null for any other host or shape - non-GitHub origins simply
/// hide the GitHub panel.
RepoSlug? githubSlugFromRemoteUrl(String url) {
  final m = _https.firstMatch(url.trim()) ?? _ssh.firstMatch(url.trim());
  if (m == null) return null;
  return (owner: m.group(1)!, repo: m.group(2)!);
}
