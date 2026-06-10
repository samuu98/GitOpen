import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/auth/auth_profile_store.dart';
import 'package:gitopen/application/auth/auth_resolver.dart';
import 'package:gitopen/application/auth/credential_tester.dart';
import 'package:gitopen/application/auth/device_flow_controller.dart';
import 'package:gitopen/application/git/git_action_ports.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/application/git/git_dir_probe.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/launcher/folder_picker.dart';
import 'package:gitopen/application/launcher/repo_launcher.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/settings/app_settings.dart';
import 'package:gitopen/application/settings/app_settings_notifier.dart';
import 'package:gitopen/application/watch/repo_watcher.dart';
import 'package:gitopen/application/workspaces/repository_registry.dart';
import 'package:gitopen/application/workspaces/workspace.dart';
import 'package:gitopen/application/workspaces/workspace_manager.dart';
import 'package:gitopen/application/workspaces/workspace_persistence.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/refs/submodule.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/infrastructure/auth/git_credential_tester.dart';
import 'package:gitopen/infrastructure/auth/github_device_flow.dart';
import 'package:gitopen/infrastructure/auth/github_user_service.dart';
import 'package:gitopen/infrastructure/auth/secure_auth_profile_store.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:gitopen/infrastructure/git/git_identity_service.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:gitopen/infrastructure/git/git_remote_url_reader.dart';
import 'package:gitopen/infrastructure/git/io_git_dir_probe.dart';
import 'package:gitopen/infrastructure/launcher/system_repo_launcher.dart';
import 'package:gitopen/infrastructure/logging/app_logger.dart';
import 'package:gitopen/infrastructure/logging/app_logger_port.dart';
import 'package:gitopen/infrastructure/operations/activity_log_repository.dart';
import 'package:gitopen/infrastructure/persistence/database.dart';
import 'package:gitopen/infrastructure/persistence/repository_registry_impl.dart';
import 'package:gitopen/infrastructure/persistence/settings_repository.dart';
import 'package:gitopen/infrastructure/persistence/workspace_persistence_impl.dart';
import 'package:gitopen/infrastructure/updates/github_release_updater.dart';
import 'package:gitopen/infrastructure/watch/io_repo_watcher.dart';
import 'package:gitopen/ui/services/folder_picker.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final gitProcessRunnerProvider = Provider<GitProcessRunner>((ref) {
  return GitProcessRunner();
});

final loggerProvider = Provider<LoggerPort>((ref) => const AppLoggerPort());

final gitReadOperationsProvider = Provider<GitReadOperations>((ref) {
  return GitCliReadOperations(runner: ref.watch(gitProcessRunnerProvider));
});

final repositoryRegistryProvider = Provider<RepositoryRegistry>((ref) {
  return DriftRepositoryRegistry(ref.watch(appDatabaseProvider));
});

final workspacePersistenceProvider = Provider<WorkspacePersistence>((ref) {
  return DriftWorkspacePersistence(ref.watch(appDatabaseProvider));
});

final workspaceManagerProvider =
    StateNotifierProvider<WorkspaceManager, List<Workspace>>((ref) {
  return WorkspaceManager(ref.watch(repositoryRegistryProvider));
});

final folderPickerProvider =
    Provider<FolderPicker>((ref) => const SystemFolderPicker());

/// Probes `.git` for in-progress-operation markers (file-system backed).
final gitDirProbeProvider =
    Provider<GitDirProbe>((ref) => const IoGitDirProbe());

/// Watches a repo's `.git` bookkeeping for external changes (auto-refresh).
final repoWatcherProvider = Provider<RepoWatcher>((ref) => IoRepoWatcher());

final gitWriteOperationsProvider = Provider<GitWriteOperations>((ref) {
  return GitCliWriteOperations(runner: ref.watch(gitProcessRunnerProvider));
});

/// Extracts user-presentable text from a thrown git transport error — the
/// composition root is the one place allowed to know how to read git's
/// stderr off a `GitProcessException` (UI gets the function, not the type).
final gitErrorTextProvider = Provider<String Function(Object error)>(
  (ref) => (e) => e is GitProcessException ? e.stderr : e.toString(),
);

/// Pure orchestrator for git actions (progress + auth-retry + declarative
/// invalidation). The UI's `GitActionsController` drives it with concrete
/// ports.
final gitActionsServiceProvider = Provider<GitActionsService>((ref) {
  return GitActionsService(
    write: ref.watch(gitWriteOperationsProvider),
    resolveProfile: (repo) =>
        ref.read(authResolverProvider).resolveForRepo(repo),
    errorText: ref.watch(gitErrorTextProvider),
  );
});

final activityLogRepositoryProvider = Provider<ActivityLogRepository>((ref) {
  return ActivityLogRepository(ref.watch(appDatabaseProvider));
});

final operationsProvider =
    StateNotifierProvider<OperationsNotifier, List<RunningOperation>>((ref) {
  return OperationsNotifier(ref.watch(activityLogRepositoryProvider));
});

final authProfileStoreProvider = Provider<AuthProfileStore>(
  (ref) => SecureAuthProfileStore(),
);

final authResolverProvider = Provider<AuthResolver>((ref) {
  final store = ref.watch(authProfileStoreProvider);
  return AuthResolver(
    store,
    remoteUrl: GitRemoteUrlReader(runner: ref.watch(gitProcessRunnerProvider)),
    // Always reads the current binding map from settings — closure runs once
    // per resolve, so the provider does not need to rebuild on settings change.
    bindingLookup: (repoId) =>
        ref.read(appSettingsProvider).authRepoBindings[repoId],
    log: ref.watch(loggerProvider),
  );
});

/// Cached resolve of "which profile should this repo use right now".
///
/// Use this from UI instead of calling [AuthResolver.resolveForRepo]
/// directly inside a `build()` method.  The naive `FutureBuilder(future:
/// resolver.resolveForRepo(repo))` pattern recreates the future on every
/// rebuild → completion triggers another rebuild → another future → an
/// infinite loop that spawns `git remote get-url` repeatedly and locks the
/// app.  This provider caches by [RepoLocation] (Equatable) and only
/// re-runs when the binding map actually changes.
/// Shared status fetch — provides ahead/behind for the current branch (the
/// status bar reads this) as well as the working-tree entries used by the
/// changes panel.  Centralised so multiple consumers don't each spawn a
/// `git status` of their own.
final FutureProviderFamily<RepoStatus, RepoLocation> repoStatusProvider =
    FutureProvider.family<RepoStatus, RepoLocation>((ref, repo) {
  return ref.watch(gitReadOperationsProvider).getStatus(repo);
});

/// Local branches only — always fast.  This is what the UI awaits on
/// initial repo load so the graph and sidebar render immediately.
final FutureProviderFamily<List<Branch>, RepoLocation> localBranchesProvider =
    FutureProvider.family<List<Branch>, RepoLocation>((ref, repo) {
  appLog.i('branches: loading locals for ${repo.displayName}');
  return ref.watch(gitReadOperationsProvider).getLocalBranches(repo);
});

/// Remote tracking branches — may take seconds (or time out at 3s on
/// huge monorepos).  Loaded in parallel and consumed without `await` by
/// UI that wants to render incrementally.
final FutureProviderFamily<List<Branch>, RepoLocation> remoteBranchesProvider =
    FutureProvider.family<List<Branch>, RepoLocation>((ref, repo) {
  appLog.i('branches: loading remotes for ${repo.displayName}');
  return ref.watch(gitReadOperationsProvider).getRemoteBranches(repo);
});

/// Combined locals + remotes.  Resolves only after BOTH lists are ready
/// (remotes is internally capped at 3s — see
/// [GitCliReadOperations.getRemoteBranches]).
///
/// IMPORTANT: this provider must NOT re-emit after first resolving.  An
/// earlier version watched [remoteBranchesProvider] as an AsyncValue and
/// re-emitted when remotes arrived; that caused every downstream provider
/// (graph, sidebar) to RE-RUN from scratch, doubling the `git log` cost
/// and blocking the UI on big repos.  Always await both `.future`s here.
final FutureProviderFamily<List<Branch>, RepoLocation> branchesProvider =
    FutureProvider.family<List<Branch>, RepoLocation>((ref, repo) async {
  final locals = await ref.watch(localBranchesProvider(repo).future);
  final remotes = await ref.watch(remoteBranchesProvider(repo).future);
  return [...locals, ...remotes];
});

/// Submodules registered in the superproject (`git submodule status`).
/// Family-keyed by [RepoLocation] like the other ref providers.
final FutureProviderFamily<List<Submodule>, RepoLocation> submodulesProvider =
    FutureProvider.family<List<Submodule>, RepoLocation>((ref, repo) {
  return ref.watch(gitReadOperationsProvider).getSubmodules(repo);
});

final AutoDisposeFutureProviderFamily<AuthProfile?, RepoLocation>
    repoActiveProfileProvider = FutureProvider.autoDispose
        .family<AuthProfile?, RepoLocation>((ref, repo) async {
  ref.watch(appSettingsProvider.select((s) => s.authRepoBindings));
  appLog.i('auth: resolveForRepo(${repo.displayName}) starting');
  final profile = await ref.read(authResolverProvider).resolveForRepo(repo);
  appLog.i('auth: resolveForRepo(${repo.displayName}) → '
      '${profile?.label ?? "none"}');
  return profile;
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(appDatabaseProvider));
});

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettingsState>((ref) {
  return AppSettingsNotifier(ref.watch(settingsRepositoryProvider));
});

final updaterProvider = Provider<GitHubReleaseUpdater>((ref) {
  return GitHubReleaseUpdater();
});

final gitIdentityServiceProvider = Provider<GitIdentityService>((ref) {
  return GitIdentityService(runner: ref.watch(gitProcessRunnerProvider));
});

final repoLauncherProvider = Provider<RepoLauncher>((ref) {
  return SystemRepoLauncher();
});

final credentialTesterProvider = Provider<CredentialTester>((ref) {
  return const GitCredentialTester();
});

final gitHubUserServiceProvider = Provider<GitHubUserService>((ref) {
  return const GitHubUserService();
});

/// Builds the [DeviceFlowPort] for a GitHub OAuth device-flow sign-in with
/// the given OAuth app client id (composition root for the infrastructure
/// HTTP client, so the auth dialog never imports infrastructure).
final deviceFlowPortProvider =
    Provider<DeviceFlowPort Function(String clientId)>((ref) {
  return (clientId) =>
      GitHubDeviceFlowPort(GitHubDeviceFlow(clientId: clientId));
});

final availableEditorsProvider = FutureProvider<List<EditorTarget>>((ref) {
  return ref.watch(repoLauncherProvider).detectAvailableEditors();
});
