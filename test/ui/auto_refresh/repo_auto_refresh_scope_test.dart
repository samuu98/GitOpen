import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/settings/app_settings_notifier.dart';
import 'package:gitopen/application/settings/settings_store.dart';
import 'package:gitopen/application/watch/repo_change.dart';
import 'package:gitopen/application/watch/repo_watcher.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/auto_refresh/repo_auto_refresh_scope.dart';

class _FakeWatcher implements RepoWatcher {
  final controller = StreamController<RepoChange>.broadcast();
  int subscriptions = 0;

  /// Currently-listening subscriptions (listen − cancel).
  int active = 0;

  @override
  Stream<RepoChange> changes(RepoLocation repo) {
    subscriptions++;
    final single = StreamController<RepoChange>()
      ..onListen = (() => active++)
      ..onCancel = (() async => active--);
    controller.stream.listen(single.add, onDone: single.close);
    return single.stream;
  }
}

class _InMemoryStore implements SettingsStore {
  final Map<String, dynamic> values = {};

  @override
  Future<Map<String, dynamic>> readAll() async => values;

  @override
  Future<void> put(String key, dynamic value) async => values[key] = value;
}

void main() {
  testWidgets('debounced watcher event invalidates the read ops provider',
      (tester) async {
    final watcher = _FakeWatcher();
    var builds = 0;
    final repo = RepoLocation(RepoId.newId(), 'unused', 't');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repoWatcherProvider.overrideWithValue(watcher),
        appSettingsProvider
            .overrideWith((ref) => AppSettingsNotifier(_InMemoryStore())),
      ],
      child: MaterialApp(
        home: RepoAutoRefreshScope(
          repo: repo,
          child: Consumer(builder: (context, ref, _) {
            // Keep gitReadOperationsProvider alive so invalidate() rebuilds
            // this consumer.
            ref.watch(gitReadOperationsProvider);
            builds++;
            return const SizedBox();
          }),
        ),
      ),
    ));
    expect(watcher.subscriptions, 1);
    expect(watcher.active, 1);
    expect(builds, 1);

    watcher.controller
      ..add(RepoChange.head)
      ..add(RepoChange.head); // burst → exactly one refresh
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(builds, 2);
    await watcher.controller.close();
  });

  testWidgets('autoRefresh off → subscription settles to none',
      (tester) async {
    final watcher = _FakeWatcher();
    final store = _InMemoryStore()..values['auto_refresh'] = false;
    final repo = RepoLocation(RepoId.newId(), 'unused', 't');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repoWatcherProvider.overrideWithValue(watcher),
        appSettingsProvider
            .overrideWith((ref) => AppSettingsNotifier(store)),
      ],
      child: MaterialApp(
        home: RepoAutoRefreshScope(repo: repo, child: const SizedBox()),
      ),
    ));
    // The notifier's async _load applies the stored auto_refresh=false; the
    // scope may briefly subscribe against the optimistic default (true) but
    // must settle unsubscribed.
    await tester.pump();
    await tester.pump();
    expect(watcher.active, 0);
    await watcher.controller.close();
  });
}
