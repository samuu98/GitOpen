import 'dart:async';
import 'dart:ui';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/active_workspace_provider.dart';
import 'application/auto_refresh/repo_change_watcher.dart';
import 'application/git/repo_state_provider.dart';
import 'application/main_view_provider.dart';
import 'application/operations/running_operation.dart';
import 'application/providers.dart';
import 'application/repo_revision.dart';
import 'application/settings/app_settings.dart';
import 'application/settings/settings_open_provider.dart';
import 'application/workspaces/workspace.dart';
import 'domain/repositories/repo_location.dart';
import 'infrastructure/logging/app_logger.dart';
import 'ui/theme/app_palette.dart';
import 'ui/theme/app_typography.dart';
import 'ui/command_palette/command_palette.dart';
import 'ui/bottom_panel/bottom_panel.dart';
import 'ui/commit_graph/commit_graph_panel.dart';
import 'ui/common/vertical_splitter.dart';
import 'ui/conflicts/conflict_resolution_panel.dart';
import 'ui/operations/toast_overlay.dart';
import 'ui/settings/settings_page.dart';
import 'ui/shell/repo_selector.dart';
import 'ui/shell/view_selector.dart';
import 'ui/sidebar/sidebar.dart';
import 'ui/status_bar/status_bar.dart';
import 'ui/toolbar/git_toolbar.dart';
import 'ui/welcome/welcome_screen.dart';
import 'ui/working_copy/working_copy_panel.dart';

final _log = appLog;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Block until the file sink is open, otherwise the very first lines we
  // log (about repo rehydration) would race the file init.
  await appLogFileOutput.init();
  _log.i('GitOpen starting — log file at '
      '${await appLogFileOutput.resolvePath()}');

  // Global error capture — without this, a thrown exception during repo
  // load can take the app down with no visible stack trace.
  FlutterError.onError = (details) {
    _log.e('FlutterError',
        error: details.exception, stackTrace: details.stack);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _log.e('PlatformDispatcher error', error: error, stackTrace: stack);
    return true;
  };

  final container = ProviderContainer();
  await _rehydrate(container);
  _subscribePersistence(container);
  _subscribeRepoSwitch(container);

  if (container.read(appSettingsProvider).autoUpdateCheck) {
    unawaited(_checkForUpdatesQuietly(container));
  }

  runApp(UncontrolledProviderScope(
    container: container,
    child: const GitOpenApp(),
  ));

  doWhenWindowReady(() {
    const initialSize = Size(1400, 900);
    appWindow.minSize = const Size(800, 500);
    appWindow.size = initialSize;
    appWindow.alignment = Alignment.center;
    appWindow.title = 'GitOpen';
    appWindow.show();
  });
}

Future<void> _rehydrate(ProviderContainer container) async {
  try {
    final persistence = container.read(workspacePersistenceProvider);
    final manager = container.read(workspaceManagerProvider.notifier);
    final paths = await persistence.getOpenPaths();
    for (final p in paths) {
      try {
        await manager.open(p);
      } catch (e) {
        _log.w('Failed to reopen workspace $p: $e');
      }
    }
    final workspaces = container.read(workspaceManagerProvider);
    if (workspaces.isNotEmpty) {
      container.read(activeWorkspaceIdProvider.notifier).state =
          workspaces.first.location.id;
    }
  } catch (e) {
    _log.w('Rehydration failed: $e');
  }
}

/// Clears per-repo selection state whenever the active workspace changes.
/// Without this the commit-details pane keeps showing the previous repo's
/// selection after switching.
void _subscribeRepoSwitch(ProviderContainer container) {
  container.listen(activeWorkspaceIdProvider, (previous, next) {
    if (previous == next) return;
    container.read(selectedCommitShaProvider.notifier).state = null;
  });
}

void _subscribePersistence(ProviderContainer container) {
  container.listen<List<Workspace>>(
    workspaceManagerProvider,
    (previous, next) async {
      final persistence = container.read(workspacePersistenceProvider);
      final paths = next.map((w) => w.location.path).toList();
      try {
        await persistence.saveOpenPaths(paths);
      } catch (e) {
        _log.w('Persist failed: $e');
      }
    },
  );
}

Future<void> _checkForUpdatesQuietly(ProviderContainer container) async {
  try {
    // Keep in sync with pubspec.yaml `version:`.
    const currentVersion = '1.0.0';
    final updater = container.read(updaterProvider);
    final newer = await updater.checkForUpdates(currentVersion);
    if (newer != null) {
      _log.i('Update available: $newer');
    }
  } catch (e) {
    _log.d('Startup update check failed (non-critical): $e');
  }
}

class GitOpenApp extends ConsumerWidget {
  const GitOpenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appSettingsProvider.select((s) => s.theme));
    final fontFamily =
        ref.watch(appSettingsProvider.select((s) => s.fontFamily));
    final fontSize = ref.watch(appSettingsProvider.select((s) => s.fontSize));
    final palette = theme == AppTheme.dark ? AppPalette.dark() : AppPalette.light();
    final typography =
        AppTypography.fromSettings(fontFamily: fontFamily, baseSize: fontSize);
    return MaterialApp(
      title: 'GitOpen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: theme == AppTheme.dark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: palette.bg1,
        fontFamily: fontFamily,
        tooltipTheme: TooltipThemeData(
          waitDuration: const Duration(milliseconds: 500),
          decoration: BoxDecoration(
            color: palette.bg5,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: palette.borderStrong),
          ),
          textStyle: typography.bodySmall.copyWith(color: palette.fg0),
        ),
        extensions: [palette, typography],
      ),
      home: const Shell(),
    );
  }
}

// ---------------------------------------------------------------------------
// Intent classes for the reactive Shortcuts block in Shell
// ---------------------------------------------------------------------------
class _CommitIntent extends Intent { const _CommitIntent(); }
class _FetchIntent extends Intent { const _FetchIntent(); }
class _OpenSettingsIntent extends Intent { const _OpenSettingsIntent(); }
class _CommandPaletteIntent extends Intent { const _CommandPaletteIntent(); }

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  /// Background auto-fetch timer (see [_reconcileAutoFetchTimer]).
  Timer? _autoFetchTimer;
  /// Encodes the current timer config so reconciliation is idempotent:
  /// the interval in minutes when enabled, or -1 when disabled.
  int? _autoFetchSig;
  /// Guards against overlapping fetches — a periodic tick is skipped while
  /// any fetch (manual or automatic) is still running.
  bool _fetchInFlight = false;

  /// One filesystem watcher per open repo (see [_reconcileRepoWatchers]).
  final Map<RepoLocation, RepoChangeWatcher> _repoWatchers = {};

  @override
  void dispose() {
    _autoFetchTimer?.cancel();
    for (final w in _repoWatchers.values) {
      w.dispose();
    }
    _repoWatchers.clear();
    super.dispose();
  }

  /// Keeps one [RepoChangeWatcher] per open repo, matching the current tabs
  /// and the auto-refresh setting. Idempotent — safe to call on every build.
  /// Watchers killed by stream errors are also pruned (and recreated) here.
  void _reconcileRepoWatchers(List<Workspace> workspaces, bool enabled) {
    final wanted = <RepoLocation>{
      if (enabled) ...workspaces.map((w) => w.location),
    };
    _repoWatchers.removeWhere((loc, watcher) {
      if (wanted.contains(loc) && watcher.isActive) return false;
      watcher.dispose();
      return true;
    });
    for (final loc in wanted) {
      _repoWatchers.putIfAbsent(
        loc,
        () => RepoChangeWatcher(
          repoRoot: loc.path,
          onChanged: () {
            if (mounted) refreshRepo(ref, loc);
          },
        ),
      );
    }
  }

  /// Starts, stops, or reschedules the background fetch timer to match the
  /// current settings. Idempotent: a no-op when the config is unchanged, so
  /// it is safe to call on every build.
  void _reconcileAutoFetchTimer(bool enabled, int minutes) {
    final sig = enabled ? minutes : -1;
    if (sig == _autoFetchSig) return;
    _autoFetchSig = sig;
    _autoFetchTimer?.cancel();
    _autoFetchTimer = null;
    if (!enabled) return;
    final interval = Duration(minutes: minutes.clamp(1, 1440));
    _autoFetchTimer = Timer.periodic(interval, (_) {
      if (_fetchInFlight) return;
      unawaited(_fetchActive(silent: true));
    });
  }

  /// Fetches the active repo. F5 / command-palette use the default (visible)
  /// mode, which drives the operations toast; the background timer uses
  /// [silent] mode, which fetches quietly and only logs failures.
  Future<void> _fetchActive({bool silent = false}) async {
    final activeId = ref.read(activeWorkspaceIdProvider);
    if (activeId == null) return;
    final workspaces = ref.read(workspaceManagerProvider);
    final active =
        workspaces.firstWhereOrNull((w) => w.location.id == activeId);
    if (active == null) return;
    final repo = active.location;
    _fetchInFlight = true;
    final ops = ref.read(operationsProvider.notifier);
    final id = silent ? null : ops.start(OpKind.fetch, 'Fetching origin', repo: repo);
    try {
      final profile = await ref.read(authResolverProvider).resolveForRepo(repo);
      if (!mounted) return;
      await for (final ev in ref
          .read(gitWriteOperationsProvider)
          .fetch(repo, auth: profile?.spec)) {
        // `ev` is a typed GitProgress — read its fields directly rather than
        // via `as dynamic`, which would crash at runtime if the shape changed.
        if (id != null) ops.updateProgress(id, ev.fraction, ev.phase);
      }
      if (id != null) ops.finishSuccess(id);
      if (mounted) refreshRepo(ref, repo);
    } catch (e) {
      if (id != null) {
        ops.finishFailure(id, e.toString());
      } else {
        _log.w('Auto-fetch failed: $e');
      }
    } finally {
      _fetchInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeId = ref.watch(activeWorkspaceIdProvider);
    final workspaces = ref.watch(workspaceManagerProvider);
    final active = activeId == null
        ? null
        : workspaces.firstWhereOrNull((w) => w.location.id == activeId);
    final settingsOpen = ref.watch(settingsOpenProvider);
    final bindings = ref.watch(appSettingsProvider.select((s) => s.keybindings));

    // F5 from the command palette / other non-key sources.
    ref.listen<int>(triggerFetchProvider, (_, _) => _fetchActive());

    // Keep the background fetch timer in sync with settings. Watching here
    // re-runs build (and reconciliation) whenever either field changes; the
    // reconcile is idempotent so repeated identical builds are harmless.
    final autoFetch = ref.watch(appSettingsProvider
        .select((s) => (s.autoFetchEnabled, s.autoFetchIntervalMinutes)));
    _reconcileAutoFetchTimer(autoFetch.$1, autoFetch.$2);

    // Same idea for the per-repo filesystem watchers behind auto-refresh.
    final autoRefresh =
        ref.watch(appSettingsProvider.select((s) => s.autoRefreshEnabled));
    _reconcileRepoWatchers(workspaces, autoRefresh);

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        if (bindings['commit'] != null) bindings['commit']!: const _CommitIntent(),
        if (bindings['fetch'] != null) bindings['fetch']!: const _FetchIntent(),
        if (bindings['openSettings'] != null) bindings['openSettings']!: const _OpenSettingsIntent(),
        if (bindings['commandPalette'] != null) bindings['commandPalette']!: const _CommandPaletteIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _CommitIntent: CallbackAction<_CommitIntent>(
            onInvoke: (_) {
              ref.read(triggerCommitProvider.notifier).state++;
              return null;
            },
          ),
          _FetchIntent: CallbackAction<_FetchIntent>(
            onInvoke: (_) { _fetchActive(); return null; },
          ),
          _OpenSettingsIntent: CallbackAction<_OpenSettingsIntent>(
            onInvoke: (_) {
              final notifier = ref.read(settingsOpenProvider.notifier);
              notifier.state = !notifier.state;
              return null;
            },
          ),
          _CommandPaletteIntent: CallbackAction<_CommandPaletteIntent>(
            onInvoke: (_) {
              CommandPalette.show(context);
              return null;
            },
          ),
        },
        child: Focus(
        autofocus: true,
        child: Builder(builder: (context) {
          final palette = AppPalette.of(context);
          return Scaffold(
          backgroundColor: palette.bg1,
          body: WindowBorder(
            color: palette.bg3,
            width: 1,
            child: Stack(children: [
              Column(
                children: [
                  const _TitleBar(),
                  Expanded(
                    child: Row(
                      children: [
                        const Sidebar(),
                        Expanded(
                          child: Container(
                            color: palette.bg1,
                            alignment: Alignment.center,
                            // Settings must win over the welcome screen:
                            // on a fresh install there is no workspace yet,
                            // but the user still needs settings to set up
                            // auth profiles before cloning anything.
                            child: settingsOpen
                                ? const SettingsPage()
                                : workspaces.isEmpty || active == null
                                    ? const WelcomeScreen()
                                    : Builder(builder: (context) {
                                            final view = ref.watch(mainViewProvider);
                                            final repoStateAsync = ref.watch(
                                                repoStateProvider(active.location));
                                            final inProgressOp =
                                                repoStateAsync.valueOrNull;
                                            final hasConflict =
                                                inProgressOp == InProgressOp.merge ||
                                                inProgressOp == InProgressOp.cherryPick ||
                                                inProgressOp == InProgressOp.rebase ||
                                                inProgressOp == InProgressOp.revert;
                                            return Column(
                                              children: [
                                                const ViewSelector(),
                                                Expanded(
                                                  child: AnimatedSwitcher(
                                                    duration: const Duration(
                                                        milliseconds: 180),
                                                    child: KeyedSubtree(
                                                      key: ValueKey(hasConflict
                                                          ? 'conflict'
                                                          : view.name),
                                                      child: hasConflict
                                                      ? ConflictResolutionPanel(
                                                          repo: active.location)
                                                      : view == MainView.changes
                                                          ? WorkingCopyPanel(
                                                              repo: active.location)
                                                          : VerticalSplitter(
                                                              initialBottom: ref
                                                                  .read(appSettingsProvider)
                                                                  .bottomPanelHeight,
                                                              onResized: (h) => ref
                                                                  .read(appSettingsProvider
                                                                      .notifier)
                                                                  .setBottomPanelHeight(h),
                                                              top: CommitGraphPanel(
                                                                  repo: active.location),
                                                              bottom: BottomPanel(
                                                                  repo: active.location),
                                                            ),
                                                    ),
                                                  ),
                                                ),
                                                const StatusBar(),
                                              ],
                                            );
                                          }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const ToastOverlay(),
            ]),
          ),
        );
        }),
      ),
      ),
    );
  }
}

class _TitleBar extends ConsumerWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return WindowTitleBarBox(
      child: Container(
        color: palette.bg3,
        child: Row(
          children: [
            // Brand: small, on its own draggable surface.
            SizedBox(height: 38, child: MoveWindow(child: const _Brand())),
            // Left drag spacer.
            Expanded(child: MoveWindow()),
            // Repo selector dropdown — non-draggable interactive area.
            const RepoSelector(),
            const SizedBox(width: 8),
            // Fetch / Pull / Push toolbar buttons.
            const GitToolbar(),
            // Right drag spacer.
            Expanded(child: MoveWindow()),
            // Settings icon button.
            IconButton(
              icon: Icon(Icons.settings, size: 16, color: palette.fg1),
              tooltip: 'Settings',
              onPressed: () =>
                  ref.read(settingsOpenProvider.notifier).state = true,
            ),
            // Window controls (min/max/close) — interactive.
            const _WindowControls(),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: palette.accentCurrent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'GitOpen',
            style: TextStyle(
              color: palette.fg0,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowControls extends StatelessWidget {
  const _WindowControls();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final colors = WindowButtonColors(
      iconNormal: palette.fg1,
      mouseOver: palette.bg4,
      mouseDown: palette.bg5,
      iconMouseOver: palette.fg0,
      iconMouseDown: palette.fg0,
    );
    final closeColors = WindowButtonColors(
      iconNormal: palette.fg1,
      mouseOver: palette.accentErr,
      mouseDown: palette.accentErr,
      iconMouseOver: Colors.white,
      iconMouseDown: Colors.white,
    );
    return Row(children: [
      MinimizeWindowButton(colors: colors),
      MaximizeWindowButton(colors: colors),
      CloseWindowButton(colors: closeColors),
    ]);
  }
}
