import 'dart:async';
import 'dart:ui';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/active_workspace_provider.dart';
import 'application/git/repo_state_provider.dart';
import 'application/main_view_provider.dart';
import 'application/operations/running_operation.dart';
import 'application/providers.dart';
import 'application/repo_revision.dart';
import 'application/settings/app_settings.dart';
import 'application/settings/settings_open_provider.dart';
import 'application/workspaces/workspace.dart';
import 'infrastructure/logging/app_logger.dart';
import 'ui/theme/app_palette.dart';
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
    const currentVersion = '0.1.0';
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
    final palette = theme == AppTheme.dark ? AppPalette.dark() : AppPalette.light();
    return MaterialApp(
      title: 'GitOpen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: theme == AppTheme.dark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: palette.bg1,
        extensions: [palette],
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

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  /// F5 — fetch the active repo.
  Future<void> _fetchActive() async {
    final activeId = ref.read(activeWorkspaceIdProvider);
    if (activeId == null) return;
    final workspaces = ref.read(workspaceManagerProvider);
    final active =
        workspaces.firstWhereOrNull((w) => w.location.id == activeId);
    if (active == null) return;
    final repo = active.location;
    final ops = ref.read(operationsProvider.notifier);
    final id = ops.start(OpKind.fetch, 'Fetching origin', repo: repo);
    final profile = await ref.read(authResolverProvider).resolveForRepo(repo);
    if (!mounted) return;
    try {
      await for (final ev in ref
          .read(gitWriteOperationsProvider)
          .fetch(repo, auth: profile?.spec)) {
        // `ev` is a typed GitProgress — read its fields directly rather than
        // via `as dynamic`, which would crash at runtime if the shape changed.
        ops.updateProgress(id, ev.fraction, ev.phase);
      }
      ops.finishSuccess(id);
      if (mounted) refreshRepo(ref, repo);
    } catch (e) {
      ops.finishFailure(id, e.toString());
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

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        if (bindings['commit'] != null) bindings['commit']!: const _CommitIntent(),
        if (bindings['fetch'] != null) bindings['fetch']!: const _FetchIntent(),
        if (bindings['openSettings'] != null) bindings['openSettings']!: const _OpenSettingsIntent(),
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
                            child: workspaces.isEmpty
                                ? const WelcomeScreen()
                                : active == null
                                    ? const WelcomeScreen()
                                    : settingsOpen
                                        ? const SettingsPage()
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
                                                  child: hasConflict
                                                      ? ConflictResolutionPanel(
                                                          repo: active.location)
                                                      : view == MainView.changes
                                                          ? WorkingCopyPanel(
                                                              repo: active.location)
                                                          : VerticalSplitter(
                                                              top: CommitGraphPanel(
                                                                  repo: active.location),
                                                              bottom: BottomPanel(
                                                                  repo: active.location),
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
