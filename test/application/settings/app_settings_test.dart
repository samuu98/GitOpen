import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git_identity/git_identity.dart';
import 'package:gitopen/application/settings/app_settings.dart';
import 'package:gitopen/application/settings/app_settings_notifier.dart';
import 'package:gitopen/infrastructure/persistence/settings_repository.dart';
import '../../_helpers/in_memory_db.dart';

void main() {
  group('AppTheme / DefaultPullStrategy enums', () {
    test('AppTheme has dark and light variants', () {
      expect(AppTheme.values, [AppTheme.dark, AppTheme.light]);
    });

    test('DefaultPullStrategy covers ffOnly, merge, rebase', () {
      expect(DefaultPullStrategy.values, [
        DefaultPullStrategy.ffOnly,
        DefaultPullStrategy.merge,
        DefaultPullStrategy.rebase,
      ]);
    });
  });

  group('AppSettingsState value object', () {
    test('applies all documented defaults', () {
      const state = AppSettingsState();
      expect(state.theme, AppTheme.dark);
      expect(state.externalEditorPath, isNull);
      expect(state.defaultPullStrategy, DefaultPullStrategy.merge);
      expect(state.commitSignoffDefault, isFalse);
      expect(state.gpgSignByDefault, isFalse);
      expect(state.fontSize, 12);
      expect(state.fontFamily, isNull);
      expect(state.githubClientId, isNull);
      expect(state.autoUpdateCheck, isTrue);
      expect(state.autoRefresh, isTrue);
      expect(state.confirmPushPull, isTrue);
      expect(state.fileListsAsTree, isFalse);
      expect(state.keybindings, isEmpty);
      expect(state.gitIdentities, isEmpty);
      expect(state.authRepoBindings, isEmpty);
    });

    test('copyWith overrides only provided fields', () {
      const state = AppSettingsState();
      final updated = state.copyWith(
        theme: AppTheme.light,
        defaultPullStrategy: DefaultPullStrategy.rebase,
        commitSignoffDefault: true,
        gpgSignByDefault: true,
        fontSize: 16,
        autoUpdateCheck: false,
      );
      expect(updated.theme, AppTheme.light);
      expect(updated.defaultPullStrategy, DefaultPullStrategy.rebase);
      expect(updated.commitSignoffDefault, isTrue);
      expect(updated.gpgSignByDefault, isTrue);
      expect(updated.fontSize, 16);
      expect(updated.autoUpdateCheck, isFalse);
      // Untouched fields retain their prior values.
      expect(updated.externalEditorPath, isNull);
      expect(updated.fontFamily, isNull);
      expect(updated.keybindings, isEmpty);
    });

    test('fileListsAsTree defaults to false and copyWith overrides it', () {
      const state = AppSettingsState();
      expect(state.fileListsAsTree, isFalse);
      expect(state.copyWith(fileListsAsTree: true).fileListsAsTree, isTrue);
      // Untouched by unrelated copyWith calls.
      expect(state.copyWith(fontSize: 14).fileListsAsTree, isFalse);
    });

    test('copyWith with no arguments is equal by value', () {
      const state = AppSettingsState(fontSize: 14, fontFamily: 'JetBrains');
      expect(state.copyWith(), equals(state));
    });

    test('copyWith null arguments keep existing values (?? semantics)', () {
      const state = AppSettingsState(
        externalEditorPath: '/usr/bin/code',
        githubClientId: 'client-123',
      );
      final copy = state.copyWith();
      expect(copy.externalEditorPath, '/usr/bin/code');
      expect(copy.githubClientId, 'client-123');
    });

    test('copyWith updates collection-valued fields', () {
      const state = AppSettingsState();
      const identity = GitIdentity(
        label: 'Work',
        name: 'Ada',
        email: 'ada@work.dev',
      );
      final updated = state.copyWith(
        gitIdentities: const [identity],
        authRepoBindings: const {'repo-1': 'profile-1'},
        keybindings: {
          'commit': LogicalKeySet(LogicalKeyboardKey.controlLeft),
        },
      );
      expect(updated.gitIdentities, const [identity]);
      expect(updated.authRepoBindings, {'repo-1': 'profile-1'});
      expect(updated.keybindings.containsKey('commit'), isTrue);
    });

    test('value equality holds for identical states', () {
      const a = AppSettingsState(theme: AppTheme.light, fontSize: 13);
      const b = AppSettingsState(theme: AppTheme.light, fontSize: 13);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('differs when any tracked field differs', () {
      const base = AppSettingsState();
      expect(base, isNot(const AppSettingsState(theme: AppTheme.light)));
      expect(base, isNot(const AppSettingsState(fontSize: 99)));
      expect(
        base,
        isNot(const AppSettingsState(commitSignoffDefault: true)),
      );
      expect(
        base,
        isNot(const AppSettingsState(gpgSignByDefault: true)),
      );
    });

    test('props enumerates all sixteen fields', () {
      const state = AppSettingsState();
      expect(state.props, hasLength(16));
    });

    test('pinnedBranches defaults empty and copyWith overrides it', () {
      const state = AppSettingsState();
      expect(state.pinnedBranches, isEmpty);
      final updated = state.copyWith(
        pinnedBranches: const {
          'repo-1': ['refs/heads/main'],
        },
      );
      expect(updated.pinnedBranches['repo-1'], ['refs/heads/main']);
    });
  });

  test('default state is dark theme + merge strategy', () async {
    final db = newInMemoryDb();
    final notifier = AppSettingsNotifier(SettingsRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notifier.state.theme, AppTheme.dark);
    expect(notifier.state.defaultPullStrategy, DefaultPullStrategy.merge);
    expect(notifier.state.commitSignoffDefault, isFalse);
    expect(notifier.state.gpgSignByDefault, isFalse);
    await db.close();
  });

  test('setGpgSignByDefault persists and re-loads', () async {
    final db = newInMemoryDb();
    final notifier = AppSettingsNotifier(SettingsRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await notifier.setGpgSignByDefault(true);
    expect(notifier.state.gpgSignByDefault, isTrue);
    // New notifier on same DB hydrates the saved value.
    final fresh = AppSettingsNotifier(SettingsRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fresh.state.gpgSignByDefault, isTrue);
    await db.close();
  });

  test('setConfirmPushPull defaults true, persists and re-loads', () async {
    final db = newInMemoryDb();
    final notifier = AppSettingsNotifier(SettingsRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notifier.state.confirmPushPull, isTrue);
    await notifier.setConfirmPushPull(false);
    expect(notifier.state.confirmPushPull, isFalse);
    // New notifier on same DB hydrates the saved value.
    final fresh = AppSettingsNotifier(SettingsRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fresh.state.confirmPushPull, isFalse);
    await db.close();
  });

  test('setTheme persists and re-loads', () async {
    final db = newInMemoryDb();
    final notifier = AppSettingsNotifier(SettingsRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await notifier.setTheme(AppTheme.light);
    expect(notifier.state.theme, AppTheme.light);
    // New notifier on same DB hydrates the saved value
    final fresh = AppSettingsNotifier(SettingsRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fresh.state.theme, AppTheme.light);
    await db.close();
  });

  test('setFileListsAsTree persists and re-loads', () async {
    final db = newInMemoryDb();
    final notifier = AppSettingsNotifier(SettingsRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notifier.state.fileListsAsTree, isFalse);
    await notifier.setFileListsAsTree(true);
    expect(notifier.state.fileListsAsTree, isTrue);
    // New notifier on same DB hydrates the saved value.
    final fresh = AppSettingsNotifier(SettingsRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fresh.state.fileListsAsTree, isTrue);
    await db.close();
  });

  test('setKeybinding stores key combo and round-trips', () async {
    final db = newInMemoryDb();
    final notifier = AppSettingsNotifier(SettingsRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final combo = LogicalKeySet(
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.keyS,
    );
    await notifier.setKeybinding('commit', combo);
    final fresh = AppSettingsNotifier(SettingsRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fresh.state.keybindings['commit'], combo);
    await db.close();
  });

  test('togglePinnedBranch pins, persists, and unpins', () async {
    final db = newInMemoryDb();
    final notifier = AppSettingsNotifier(SettingsRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await notifier.togglePinnedBranch('repo-1', 'refs/heads/main');
    expect(notifier.state.pinnedBranches['repo-1'], ['refs/heads/main']);
    // Persisted across a fresh notifier on the same DB.
    final fresh = AppSettingsNotifier(SettingsRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fresh.state.pinnedBranches['repo-1'], ['refs/heads/main']);
    // Toggling the same branch again unpins it and drops the empty repo key.
    await fresh.togglePinnedBranch('repo-1', 'refs/heads/main');
    expect(fresh.state.pinnedBranches.containsKey('repo-1'), isFalse);
    await db.close();
  });
}
