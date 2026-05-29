import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/settings/app_settings.dart';
import 'package:gitopen/application/settings/app_settings_notifier.dart';
import 'package:gitopen/infrastructure/persistence/settings_repository.dart';
import '../../_helpers/in_memory_db.dart';

void main() {
  test('default state is dark theme + merge strategy', () async {
    final db = newInMemoryDb();
    final notifier = AppSettingsNotifier(SettingsRepository(db));
    await Future.delayed(const Duration(milliseconds: 50));
    expect(notifier.state.theme, AppTheme.dark);
    expect(notifier.state.defaultPullStrategy, DefaultPullStrategy.merge);
    expect(notifier.state.commitSignoffDefault, isFalse);
    await db.close();
  });

  test('setTheme persists and re-loads', () async {
    final db = newInMemoryDb();
    final notifier = AppSettingsNotifier(SettingsRepository(db));
    await Future.delayed(const Duration(milliseconds: 50));
    await notifier.setTheme(AppTheme.light);
    expect(notifier.state.theme, AppTheme.light);
    // New notifier on same DB hydrates the saved value
    final fresh = AppSettingsNotifier(SettingsRepository(db));
    await Future.delayed(const Duration(milliseconds: 50));
    expect(fresh.state.theme, AppTheme.light);
    await db.close();
  });

  test('copyWith can clear nullable fields explicitly', () {
    const s = AppSettingsState(
      externalEditorPath: '/usr/bin/code',
      fontFamily: 'Fira Code',
      githubClientId: 'abc123',
    );
    // Omitting a field preserves it…
    expect(s.copyWith(theme: AppTheme.light).externalEditorPath,
        '/usr/bin/code');
    // …but passing null clears it (regression: previously kept the old value).
    expect(s.copyWith(externalEditorPath: null).externalEditorPath, isNull);
    expect(s.copyWith(fontFamily: null).fontFamily, isNull);
    expect(s.copyWith(githubClientId: null).githubClientId, isNull);
  });

  test('setExternalEditorPath(null) actually clears the path', () async {
    final db = newInMemoryDb();
    final notifier = AppSettingsNotifier(SettingsRepository(db));
    await Future.delayed(const Duration(milliseconds: 50));
    await notifier.setExternalEditorPath('/usr/bin/code');
    expect(notifier.state.externalEditorPath, '/usr/bin/code');
    await notifier.setExternalEditorPath(null);
    expect(notifier.state.externalEditorPath, isNull);
    await db.close();
  });

  test('togglePinnedBranch adds/removes per repo and round-trips', () async {
    final db = newInMemoryDb();
    final notifier = AppSettingsNotifier(SettingsRepository(db));
    await Future.delayed(const Duration(milliseconds: 50));

    await notifier.togglePinnedBranch('repo1', 'refs/heads/main');
    await notifier.togglePinnedBranch('repo1', 'refs/heads/dev');
    expect(notifier.state.pinnedBranches['repo1'],
        containsAll(['refs/heads/main', 'refs/heads/dev']));

    await notifier.togglePinnedBranch('repo1', 'refs/heads/main'); // unpin
    expect(notifier.state.pinnedBranches['repo1'], ['refs/heads/dev']);

    // Round-trips through the DB.
    final fresh = AppSettingsNotifier(SettingsRepository(db));
    await Future.delayed(const Duration(milliseconds: 50));
    expect(fresh.state.pinnedBranches['repo1'], ['refs/heads/dev']);
    await db.close();
  });

  test('toggleSectionCollapsed persists collapsed sections', () async {
    final db = newInMemoryDb();
    final notifier = AppSettingsNotifier(SettingsRepository(db));
    await Future.delayed(const Duration(milliseconds: 50));
    await notifier.toggleSectionCollapsed('TAGS');
    expect(notifier.state.collapsedSections, contains('TAGS'));
    final fresh = AppSettingsNotifier(SettingsRepository(db));
    await Future.delayed(const Duration(milliseconds: 50));
    expect(fresh.state.collapsedSections, contains('TAGS'));
    await db.close();
  });

  test('setKeybinding stores key combo and round-trips', () async {
    final db = newInMemoryDb();
    final notifier = AppSettingsNotifier(SettingsRepository(db));
    await Future.delayed(const Duration(milliseconds: 50));
    final combo = LogicalKeySet(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyS);
    await notifier.setKeybinding('commit', combo);
    final fresh = AppSettingsNotifier(SettingsRepository(db));
    await Future.delayed(const Duration(milliseconds: 50));
    expect(fresh.state.keybindings['commit'], combo);
    await db.close();
  });
}
