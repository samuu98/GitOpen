/// Converts a git remote URL to a browsable https URL, or null when it can't
/// produce an http(s) URL. Handles scp-style `git@host:owner/repo(.git)`,
/// `ssh://git@host/owner/repo(.git)`, and `http(s)://…(.git)`.
String? remoteWebUrl(String gitUrl) {
  final url = gitUrl.trim();
  if (url.isEmpty) return null;

  String stripGit(String s) =>
      s.endsWith('.git') ? s.substring(0, s.length - 4) : s;

  // scp-style: git@host:owner/repo.git
  final scp = RegExp(r'^[^@/]+@([^:/]+):(.+)$').firstMatch(url);
  if (scp != null && !url.contains('://')) {
    return 'https://${scp.group(1)}/${stripGit(scp.group(2)!)}';
  }
  // ssh://[user@]host/owner/repo.git  or  git://host/...
  final ssh = RegExp(r'^(?:ssh|git)://(?:[^@/]+@)?([^/]+)/(.+)$').firstMatch(url);
  if (ssh != null) {
    return 'https://${ssh.group(1)}/${stripGit(ssh.group(2)!)}';
  }
  // http(s)://…
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return stripGit(url);
  }
  return null;
}
