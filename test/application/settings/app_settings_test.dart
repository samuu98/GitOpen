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
