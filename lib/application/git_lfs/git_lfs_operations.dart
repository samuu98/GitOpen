import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/git/git_progress.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git_lfs/git_lfs_models.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

abstract interface class GitLfsOperations {
  Future<GitLfsStatus> status(RepoLocation repo);
  Future<List<GitLfsTrackedPattern>> trackedPatterns(RepoLocation repo);
  Future<List<GitLfsFile>> files(RepoLocation repo);
  Future<GitResult<void>> installLocal(RepoLocation repo);
  Future<GitResult<void>> track(RepoLocation repo, String pattern);
  Future<GitResult<void>> untrack(RepoLocation repo, String pattern);
  Stream<GitProgress> fetch(RepoLocation repo, {AuthSpec? auth});
  Stream<GitProgress> pull(RepoLocation repo, {AuthSpec? auth});
  Stream<GitProgress> push(RepoLocation repo, {AuthSpec? auth});
}
