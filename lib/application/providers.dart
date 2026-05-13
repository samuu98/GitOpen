import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/credentials_store.dart';
import 'commit_graph/commit_graph_layout.dart';
import 'git/git_read_operations.dart';
import 'git/git_write_operations.dart';
import 'operations/operations_notifier.dart';
import 'operations/running_operation.dart';
import 'settings/app_settings.dart';
import 'settings/app_settings_notifier.dart';
import 'workspaces/repository_registry.dart';
import 'workspaces/workspace.dart';
import 'workspaces/workspace_manager.dart';
import 'workspaces/workspace_persistence.dart';
import '../infrastructure/auth/secure_credentials_store.dart';
import '../infrastructure/git/git_cli_read_operations.dart';
import '../infrastructure/git/git_cli_write_operations.dart';
import '../infrastructure/git/git_process_runner.dart';
import '../infrastructure/operations/activity_log_repository.dart';
import '../infrastructure/persistence/database.dart';
import '../infrastructure/persistence/repository_registry_impl.dart';
import '../infrastructure/persistence/settings_repository.dart';
import '../infrastructure/persistence/workspace_persistence_impl.dart';
import '../ui/services/folder_picker.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final gitProcessRunnerProvider = Provider<GitProcessRunner>((ref) {
  return GitProcessRunner();
});

final gitReadOperationsProvider = Provider<GitReadOperations>((ref) {
  return GitCliReadOperations(runner: ref.watch(gitProcessRunnerProvider));
});

final repositoryRegistryProvider = Provider<RepositoryRegistry>((ref) {
  return DriftRepositoryRegistry(ref.watch(appDatabaseProvider));
});

final workspacePersistenceProvider = Provider<WorkspacePersistence>((ref) {
  return DriftWorkspacePersistence(ref.watch(appDatabaseProvider));
});

final commitGraphLayoutProvider = Provider<CommitGraphLayout>((ref) {
  return const DefaultCommitGraphLayout();
});

final workspaceManagerProvider =
    StateNotifierProvider<WorkspaceManager, List<Workspace>>((ref) {
  return WorkspaceManager(ref.watch(repositoryRegistryProvider));
});

final folderPickerProvider = Provider<FolderPicker>((ref) => FolderPicker());

final gitWriteOperationsProvider = Provider<GitWriteOperations>((ref) {
  return GitCliWriteOperations(runner: ref.watch(gitProcessRunnerProvider));
});

final activityLogRepositoryProvider = Provider<ActivityLogRepository>((ref) {
  return ActivityLogRepository(ref.watch(appDatabaseProvider));
});

final operationsProvider = StateNotifierProvider<OperationsNotifier, List<RunningOperation>>((ref) {
  return OperationsNotifier(ref.watch(activityLogRepositoryProvider));
});

final credentialsStoreProvider = Provider<CredentialsStore>(
  (ref) => SecureCredentialsStore(),
);

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(appDatabaseProvider));
});

final appSettingsProvider = StateNotifierProvider<AppSettingsNotifier, AppSettingsState>((ref) {
  return AppSettingsNotifier(ref.watch(settingsRepositoryProvider));
});
