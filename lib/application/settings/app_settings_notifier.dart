import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git_identity/git_identity.dart';
import 'package:gitopen/application/settings/app_settings.dart';
import 'package:gitopen/application/settings/settings_store.dart';

const _defaultBindings = <String, List<LogicalKeyboardKey>>{
  'commit': [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.enter],
  'commitAndPush': [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.enter,
  ],
  'fetch': [LogicalKeyboardKey.f5],
  'refresh': [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyR],
  'openRepoSelector': [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyT],
  'openSettings': [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.comma],
  'commandPalette': [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyP],
};

class AppSettingsNotifier extends StateNotifier<AppSettingsState> {
  AppSettingsNotifier(this._repo) : super(_defaults()) {
    unawaited(_load());
  }
  final SettingsStore _repo;

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
      defaultPullStrategy: _enumFromString(
        all['default_pull_strategy'],
        DefaultPullStrategy.values,
        DefaultPullStrategy.merge,
      ),
      commitSignoffDefault: (all['commit_signoff_default'] as bool?) ?? false,
      gpgSignByDefault: (all['gpg_sign_by_default'] as bool?) ?? false,
      fontSize: (all['font_size'] as int?) ?? 12,
      fontFamily: all['font_family'] as String?,
      githubClientId: all['github_client_id'] as String?,
      autoUpdateCheck: (all['auto_update_check'] as bool?) ?? true,
      autoRefresh: (all['auto_refresh'] as bool?) ?? true,
      fileListsAsTree: (all['file_lists_as_tree'] as bool?) ?? false,
      keybindings: _decodeBindings(all['keybindings']) ?? state.keybindings,
      gitIdentities: _decodeIdentities(all['git_identities']),
      authRepoBindings: _decodeStringMap(all['auth_repo_bindings']),
      pinnedBranches: _decodeStringListMap(all['pinned_branches']),
    );
  }

  /// Pins/unpins [fullName] for [repoId]; an empty list drops the repo key.
  Future<void> togglePinnedBranch(String repoId, String fullName) async {
    final next = <String, List<String>>{
      for (final e in state.pinnedBranches.entries)
        e.key: List<String>.from(e.value),
    };
    final list = next.putIfAbsent(repoId, () => <String>[]);
    if (!list.remove(fullName)) list.add(fullName);
    if (list.isEmpty) next.remove(repoId);
    state = state.copyWith(pinnedBranches: next);
    await _repo.put('pinned_branches', next);
  }

  Map<String, List<String>> _decodeStringListMap(dynamic v) {
    if (v is! Map) return const {};
    final result = <String, List<String>>{};
    v.forEach((k, val) {
      if (k is String && val is List) {
        final items = val.whereType<String>().toList();
        if (items.isNotEmpty) result[k] = items;
      }
    });
    return result;
  }

  Future<void> setAuthBinding(String repoId, String? profileId) async {
    final next = Map<String, String>.from(state.authRepoBindings);
    if (profileId == null) {
      next.remove(repoId);
    } else {
      next[repoId] = profileId;
    }
    state = state.copyWith(authRepoBindings: next);
    await _repo.put('auth_repo_bindings', next);
  }

  Map<String, String> _decodeStringMap(dynamic v) {
    if (v is! Map) return const {};
    final result = <String, String>{};
    v.forEach((k, val) {
      if (k is String && val is String) result[k] = val;
    });
    return result;
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

  // Positional bool retained so the method can be used as a void Function(bool)
  // tear-off for a Switch's onChanged callback in the settings UI.
  // ignore: avoid_positional_boolean_parameters
  Future<void> setCommitSignoffDefault(bool v) async {
    state = state.copyWith(commitSignoffDefault: v);
    await _repo.put('commit_signoff_default', v);
  }

  // Positional bool retained so the method can be used as a void Function(bool)
  // tear-off for a Switch's onChanged callback in the settings UI.
  // ignore: avoid_positional_boolean_parameters
  Future<void> setAutoRefresh(bool v) async {
    state = state.copyWith(autoRefresh: v);
    await _repo.put('auto_refresh', v);
  }

  // Positional bool retained so the method can be used as a void Function(bool)
  // tear-off for a Switch's onChanged callback in the settings UI.
  // ignore: avoid_positional_boolean_parameters
  Future<void> setFileListsAsTree(bool v) async {
    state = state.copyWith(fileListsAsTree: v);
    await _repo.put('file_lists_as_tree', v);
  }

  // Positional bool retained so the method can be used as a void Function(bool)
  // tear-off for a Switch's onChanged callback in the settings UI.
  // ignore: avoid_positional_boolean_parameters
  Future<void> setGpgSignByDefault(bool v) async {
    state = state.copyWith(gpgSignByDefault: v);
    await _repo.put('gpg_sign_by_default', v);
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

  // Positional bool retained so the method can be used as a void Function(bool)
  // tear-off for a Switch's onChanged callback in the settings UI.
  // ignore: avoid_positional_boolean_parameters
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

  Future<void> addGitIdentity(GitIdentity identity) async {
    final next = [...state.gitIdentities, identity];
    state = state.copyWith(gitIdentities: next);
    await _repo.put('git_identities', next.map((i) => i.toJson()).toList());
  }

  Future<void> removeGitIdentity(int index) async {
    if (index < 0 || index >= state.gitIdentities.length) return;
    final next = [...state.gitIdentities]..removeAt(index);
    state = state.copyWith(gitIdentities: next);
    await _repo.put('git_identities', next.map((i) => i.toJson()).toList());
  }

  List<GitIdentity> _decodeIdentities(dynamic v) {
    if (v is! List) return const [];
    return v
        .map(GitIdentity.fromJson)
        .whereType<GitIdentity>()
        .toList(growable: false);
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
        final keys = ids
            .map(LogicalKeyboardKey.findKeyByKeyId)
            .whereType<LogicalKeyboardKey>()
            .toSet();
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
