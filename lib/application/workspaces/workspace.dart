import '../../domain/commits/commit_sha.dart';
import '../../domain/repositories/repo_location.dart';

final class Workspace {
  final RepoLocation location;
  String? selectedBranchFullName;
  CommitSha? selectedSha;
  int scrollOffset;

  Workspace(this.location, {
    this.selectedBranchFullName,
    this.selectedSha,
    this.scrollOffset = 0,
  });
}
