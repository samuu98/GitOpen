import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../infrastructure/persistence/settings_repository.dart';
import 'app_settings.dart';

const _defaultBindings = <String, List<LogicalKeyboardKey>>{
  'commit': [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.enter],
  'commitAndPush': [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.enter],
  'fetch': [LogicalKeyboardKey.f5],
  'refresh': [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyR],
  'openRepoSelector': [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyT],
  'openSettings': [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.comma],
};

class AppSettingsNotifier extends StateNotifier<AppSettingsState> {
  final SettingsRepository _repo;
  AppSettingsNotifier(this._repo) : super(_defaults()) {
    _load();
  }

  static AppSettingsState _defaults() {
    final defaults = <String, LogicalKeySet>{};
    for (final entry in _defaultBindings.entries) {
      defaults[entry.key] = LogicalKeySet.fromSet(entry.value.toSet());
    }
    return AppSettingsState(keybindings: defaults);
  }

  Future<void> _load() async {
    final all = await _repo.readAll();
    state = AppSettingsState(
      theme: _enumFromString(all['theme'], AppTheme.values, AppTheme.dark),
      externalEditorPath: all['external_editor_path'] as String?,
      defaultPullStrategy: _enumFromString(all['default_pull_strategy'], DefaultPullStrategy.values, DefaultPullStrategy.merge),
      commitSignoffDefault: (all['commit_signoff_default'] as bool?) ?? false,
      fontSize: (all['font_size'] as int?) ?? 12,
      fontFamily: all['font_family'] as String?,
      githubClientId: all['github_client_id'] as String?,
      autoUpdateCheck: (all['auto_update_check'] as bool?) ?? true,
      keybindings: _decodeBindings(all['keybindings']) ?? state.keybindings,
    );
  }

  Future<void> setTheme(AppTheme v) async {
    state = state.copyWith(theme: v);
    await _repo.put('theme', v.name);
  }

  Future<void> setExternalEditorPath(String? v) async {
    state = state.copyWith(externalEditorPath: v);
    await _repo.put('external_editor_path', v);
  }

  Future<void> setDefaultPullStrategy(DefaultPullStrategy v) async {
    state = state.copyWith(defaultPullStrategy: v);
    await _repo.put('default_pull_strategy', v.name);
  }

  Future<void> setCommitSignoffDefault(bool v) async {
    state = state.copyWith(commitSignoffDefault: v);
    await _repo.put('commit_signoff_default', v);
  }

  Future<void> setFontSize(int v) async {
    state = state.copyWith(fontSize: v);
    await _repo.put('font_size', v);
  }

  Future<void> setFontFamily(String? v) async {
    state = state.copyWith(fontFamily: v);
    await _repo.put('font_family', v);
  }

  Future<void> setGithubClientId(String? v) async {
    state = state.copyWith(githubClientId: v);
    await _repo.put('github_client_id', v);
  }

  Future<void> setAutoUpdateCheck(bool v) async {
    state = state.copyWith(autoUpdateCheck: v);
    await _repo.put('auto_update_check', v);
  }

  Future<void> setKeybinding(String action, LogicalKeySet keys) async {
    final next = Map<String, LogicalKeySet>.from(state.keybindings);
    next[action] = keys;
    state = state.copyWith(keybindings: next);
    await _repo.put('keybindings', _encodeBindings(next));
  }

  Future<void> resetKeybinding(String action) async {
    final defaults = _defaults().keybindings;
    if (!defaults.containsKey(action)) return;
    await setKeybinding(action, defaults[action]!);
  }

  T _enumFromString<T extends Enum>(dynamic v, List<T> values, T fallback) {
    if (v is! String) return fallback;
    return values.firstWhere((e) => e.name == v, orElse: () => fallback);
  }

  Map<String, LogicalKeySet>? _decodeBindings(dynamic v) {
    if (v is! Map) return null;
    final result = <String, LogicalKeySet>{};
    v.forEach((key, value) {
      if (key is String && value is List) {
        final ids = value.cast<int>();
        final keys = ids.map(LogicalKeyboardKey.findKeyByKeyId).whereType<LogicalKeyboardKey>().toSet();
        if (keys.isNotEmpty) result[key] = LogicalKeySet.fromSet(keys);
      }
    });
    return result;
  }

  Map<String, List<int>> _encodeBindings(Map<String, LogicalKeySet> b) {
    return {
      for (final entry in b.entries)
        entry.key: entry.value.keys.map((k) => k.keyId).toList(),
    };
  }
}
