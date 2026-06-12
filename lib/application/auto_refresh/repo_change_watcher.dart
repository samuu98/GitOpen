import 'package:path/path.dart' as p;

/// Git state files inside `.git/` whose change means "repo state moved".
const _gitStateFiles = {
  'HEAD', 'ORIG_HEAD', 'MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD',
  'index', 'packed-refs',
};

/// Whether a filesystem event at [eventPath] implies the repo at [repoRoot]
/// changed in a way the UI should reflect.
///
/// Working-tree paths always count (they drive the working-copy panel).
/// Inside `.git/` only ref updates and the well-known state files count;
/// object/pack writes, reflogs and `*.lock` churn are noise.
bool isRelevantRepoEvent(String repoRoot, String eventPath) {
  final rel = p.relative(eventPath, from: repoRoot).replaceAll('\\', '/');
  if (rel != '.git' && !rel.startsWith('.git/')) return true;
  if (rel == '.git') return false;
  final inner = rel.substring('.git/'.length);
  if (inner.endsWith('.lock')) return false;
  return _gitStateFiles.contains(inner) || inner.startsWith('refs/');
}
