import 'dart:async';
import 'dart:ui';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/git/repo_state_provider.dart';
import 'package:gitopen/application/main_view_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/settings/app_settings.dart';
import 'package:gitopen/application/settings/settings_open_provider.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/logging/app_logger.dart';
import 'package:gitopen/ui/auto_refresh/repo_auto_refresh_scope.dart';
import 'package:gitopen/ui/bottom_panel/bottom_panel.dart';
import 'package:gitopen/ui/command_palette/command_palette.dart';
import 'package:gitopen/ui/commit_graph/commit_graph_panel.dart';
import 'package:gitopen/ui/commit_graph/detached_head_banner.dart';
import 'package:gitopen/ui/common/app_scroll_configuration.dart';
import 'package:gitopen/ui/common/horizontal_splitter.dart';
import 'package:gitopen/ui/common/vertical_splitter.dart';
import 'package:gitopen/ui/conflicts/conflict_resolution_panel.dart';
import 'package:gitopen/ui/dialogs/repo_info_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/github/github_panel.dart';
import 'package:gitopen/ui/lfs/lfs_panel.dart';
import 'package:gitopen/ui/operations/blocking_overlay.dart';
import 'package:gitopen/ui/operations/toast_overlay.dart';
import 'package:gitopen/ui/settings/settings_page.dart';
import 'package:gitopen/ui/shell/repo_selector.dart';
import 'package:gitopen/ui/shell/shell_body.dart';
import 'package:gitopen/ui/shell/view_selector.dart';
import 'package:gitopen/ui/sidebar/sidebar.dart';
import 'package:gitopen/ui/status_bar/status_bar.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/toolbar/git_toolbar.dart';
import 'package:gitopen/ui/welcome/welcome_screen.dart';
import 'package:gitopen/ui/working_copy/working_copy_panel.dart';
import 'package:logger/logger.dart';

final Logger _log = appLog;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Block until the file sink is open, otherwise the very first lines we
  // log (about repo rehydration) would race the file init.
  await appLogFileOutput.init();
  _log.i(
    'GitOpen starting — log file at '
    '${await appLogFileOutput.resolvePath()}',
  );

  // Global error capture — without this, a thrown exception during repo
  // load can take the app down with no visible stack trace.
  FlutterError.onError = (details) {
    _log.e('FlutterError', error: details.exception, stackTrace: details.stack);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _log.e('PlatformDispatcher error', error: error, stackTrace: stack);
    return true;
  };

  // Records every app lifecycle transition to the log file. Diagnostic for the
  // "black, unclickable window after the app has been in the background"
  // freeze: if the log ends on a `resumed` line with no following `first frame
  // after resume` line, the engine stopped producing frames on restore (native
  // render/surface path) rather than Dart logic hanging. The listener registers
  // itself with WidgetsBinding, which retains it for the process lifetime, so
  // we don't need to hold the reference.
  AppLifecycleListener(
    onStateChange: (state) {
      _log.i('Lifecycle → $state');
      if (state == AppLifecycleState.resumed) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _log.i('First frame after resume rendered'),
        );
      }
    },
  );

  final container = ProviderContainer();
  await _rehydrate(container);
  _subscribePersistence(container);
  _subscribeRepoSwitch(container);

  if (container.read(appSettingsProvider).autoUpdateCheck) {
    unawaited(_checkForUpdatesQuietly(container));
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const GitOpenApp(),
    ),
  );

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
    final manager = container.read(workspaceManagerProvider.notifier);
    await manager.loadAll();
    await container.read(repoOrganizerProvider.notifier).refresh();

    final persistence = container.read(workspacePersistenceProvider);
    final lastId = await persistence.getLastActiveRepoId();
    final workspaces = container.read(workspaceManagerProvider);
    final restored = workspaces
        .where((w) => w.location.id.value == lastId)
        .map((w) => w.location.id)
        .firstOrNull;
    container.read(activeWorkspaceIdProvider.notifier).state =
        restored ?? (workspaces.isEmpty ? null : workspaces.first.location.id);
  } on Object catch (e) {
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
    container.read(localChangesSelectedProvider.notifier).state = false;
  });
}

void _subscribePersistence(ProviderContainer container) {
  container.listen<RepoId?>(activeWorkspaceIdProvider, (previous, next) async {
    final persistence = container.read(workspacePersistenceProvider);
    try {
      await persistence.saveLastActiveRepoId(next?.value);
    } on Object catch (e) {
      _log.w('Persist active repo failed: $e');
    }
  });
}

Future<void> _checkForUpdatesQuietly(ProviderContainer container) async {
  try {
    final currentVersion = await container.read(appVersionProvider.future);
    final updater = container.read(updaterProvider);
    final newer = await updater.checkForUpdates(currentVersion);
    if (newer != null) {
      _log.i('Update available: $newer');
    }
  } on Object catch (e) {
    _log.d('Startup update check failed (non-critical): $e');
  }
}

class GitOpenApp extends ConsumerWidget {
  const GitOpenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appSettingsProvider.select((s) => s.theme));
    final palette = theme == AppTheme.dark
        ? AppPalette.dark()
        : AppPalette.light();
    const spacing = AppSpacing.desktop();
    const radii = AppRadii.desktop();
    const typography = AppTypography.desktop();
    const motion = AppMotion.standard();
    return MaterialApp(
      title: 'GitOpen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: theme == AppTheme.dark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: palette.bg1,
        splashFactory: InkSparkle.splashFactory,
        hoverColor: palette.bg3,
        focusColor: palette.accentRemote.withValues(alpha: 0.22),
        tooltipTheme: TooltipThemeData(
          waitDuration: motion.slow,
          showDuration: const Duration(seconds: 4),
          decoration: BoxDecoration(
            color: palette.bg5,
            borderRadius: radii.controlRadius,
            border: Border.all(color: palette.borderStrong),
          ),
          textStyle: typography.caption.copyWith(color: palette.fg0),
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.hovered)
                ? palette.fg2
                : palette.fg3.withValues(alpha: 0.65);
          }),
          trackColor: WidgetStateProperty.all(palette.bg2),
          radius: Radius.circular(radii.pill),
          thickness: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.hovered) ? 8 : 6;
          }),
        ),
        extensions: [palette, spacing, radii, typography, motion],
      ),
      builder: (context, child) =>
          AppScrollConfiguration(child: child ?? const SizedBox.shrink()),
      home: const Shell(),
    );
  }
}

// ---------------------------------------------------------------------------
// Intent classes for the reactive Shortcuts block in Shell
// ---------------------------------------------------------------------------
class _CommitIntent extends Intent {
  const _CommitIntent();
}

class _CommitAndPushIntent extends Intent {
  const _CommitAndPushIntent();
}

class _FetchIntent extends Intent {
  const _FetchIntent();
}

class _OpenSettingsIntent extends Intent {
  const _OpenSettingsIntent();
}

class _CommandPaletteIntent extends Intent {
  const _CommandPaletteIntent();
}

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  /// F5 — fetch the active repo through the shared git-actions controller, so
  /// it gets the same progress + auth-retry as the toolbar's Fetch button.
  Future<void> _fetchActive() async {
    final activeId = ref.read(activeWorkspaceIdProvider);
    if (activeId == null) return;
    final workspaces = ref.read(workspaceManagerProvider);
    final active = workspaces.firstWhereOrNull(
      (w) => w.location.id == activeId,
    );
    if (active == null) return;
    await ref
        .read(gitActionsControllerProvider)
        .fetch(context, active.location);
  }

  /// Opens the command palette and runs the chosen command with the Shell's
  /// own (live) context + ref, so actions outlive the dismissed palette.
  Future<void> _openCommandPalette() async {
    final cmd = await CommandPalette.show(context);
    if (cmd == null || !mounted) return;
    await cmd.run(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    final activeId = ref.watch(activeWorkspaceIdProvider);
    final workspaces = ref.watch(workspaceManagerProvider);
    final active = activeId == null
        ? null
        : workspaces.firstWhereOrNull((w) => w.location.id == activeId);
    final settingsOpen = ref.watch(settingsOpenProvider);
    final bindings = ref.watch(
      appSettingsProvider.select((s) => s.keybindings),
    );

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        if (bindings['commit'] != null)
          bindings['commit']!: const _CommitIntent(),
        if (bindings['commitAndPush'] != null)
          bindings['commitAndPush']!: const _CommitAndPushIntent(),
        if (bindings['fetch'] != null) bindings['fetch']!: const _FetchIntent(),
        if (bindings['openSettings'] != null)
          bindings['openSettings']!: const _OpenSettingsIntent(),
        if (bindings['commandPalette'] != null)
          bindings['commandPalette']!: const _CommandPaletteIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _CommitIntent: CallbackAction<_CommitIntent>(
            onInvoke: (_) {
              ref.read(triggerCommitProvider.notifier).state++;
              return null;
            },
          ),
          _CommitAndPushIntent: CallbackAction<_CommitAndPushIntent>(
            onInvoke: (_) {
              ref.read(triggerCommitAndPushProvider.notifier).state++;
              return null;
            },
          ),
          _FetchIntent: CallbackAction<_FetchIntent>(
            onInvoke: (_) {
              unawaited(_fetchActive());
              return null;
            },
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
              unawaited(_openCommandPalette());
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Builder(
            builder: (context) {
              final palette = AppPalette.of(context);
              final shellBody = shellBodyFor(
                settingsOpen: settingsOpen,
                hasActiveRepo: active != null,
              );
              return Scaffold(
                backgroundColor: palette.bg1,
                body: WindowBorder(
                  color: palette.bg3,
                  width: 1,
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          const _TitleBar(),
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final mainArea = Container(
                                  color: palette.bg1,
                                  alignment: Alignment.center,
                                  // Settings must win over the empty/welcome
                                  // state, else a catalog with no repos makes
                                  // the Settings button unreachable.
                                  child: switch (shellBody) {
                                    ShellBody.settings => const SettingsPage(),
                                    ShellBody.welcome => const WelcomeScreen(),
                                    ShellBody.repo =>
                                      _RepoBody(repo: active!.location),
                                  },
                                );
                                // The branches/remotes/tags sidebar is hidden
                                // while Settings is open, so the settings page
                                // gets the full width. Otherwise it is the
                                // resizable left pane of a HorizontalSplitter
                                // (drag the handle to widen, double-click to
                                // reset) — same pattern as the Changes panel.
                                if (shellBody == ShellBody.settings) {
                                  return mainArea;
                                }
                                return HorizontalSplitter(
                                  defaultLeft: 260,
                                  minLeft: 180,
                                  minRight: 360,
                                  left: const Sidebar(),
                                  right: mainArea,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const ToastOverlay(),
                      const BlockingOverlay(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The main repo content area shown once a workspace is active and the
/// settings page is closed.
class _RepoBody extends ConsumerWidget {
  const _RepoBody({required this.repo});

  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(mainViewProvider);
    final repoStateAsync = ref.watch(repoStateProvider(repo));
    final inProgressOp = repoStateAsync.value;
    // Every in-progress sequencer op (merge, cherry-pick, revert AND rebase)
    // routes to the conflict panel — a paused `git rebase` previously left
    // the user with no continue/abort UI at all.
    final hasConflict =
        inProgressOp != null && inProgressOp != InProgressOp.none;
    return RepoAutoRefreshScope(
      repo: repo,
      child: Column(
        children: [
          ViewSelector(repo: repo),
          DetachedHeadBanner(repo: repo),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppMotion.of(context).normal,
              switchInCurve: AppMotion.of(context).curve,
              switchOutCurve: Curves.easeInCubic,
              child: KeyedSubtree(
                key: ValueKey(hasConflict ? 'conflict' : view.name),
                child: hasConflict
                    ? ConflictResolutionPanel(repo: repo)
                    : view == MainView.changes
                    ? WorkingCopyPanel(repo: repo)
                    : view == MainView.github
                    ? GitHubPanel(repo: repo)
                    : view == MainView.lfs
                    ? LfsPanel(repo: repo)
                    : VerticalSplitter(
                        top: CommitGraphPanel(repo: repo),
                        bottom: BottomPanel(repo: repo),
                      ),
              ),
            ),
          ),
          const StatusBar(),
        ],
      ),
    );
  }
}

class _TitleBar extends ConsumerWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final workspaces = ref.watch(workspaceManagerProvider);
    final activeId = ref.watch(activeWorkspaceIdProvider);
    final active = activeId == null
        ? null
        : workspaces.firstWhereOrNull((w) => w.location.id == activeId);
    return WindowTitleBarBox(
      child: ColoredBox(
        color: palette.bg3,
        child: Row(
          children: [
            // Brand: small, on its own draggable surface.
            SizedBox(height: 38, child: MoveWindow(child: const _Brand())),
            // Left drag spacer.
            Expanded(child: MoveWindow()),
            // Repo selector dropdown — non-draggable interactive area.
            const RepoSelector(),
            // Repository info (path / remote / git user) for the active repo.
            if (active != null)
              IconButton(
                icon: Icon(Icons.info_outline, size: 15, color: palette.fg2),
                tooltip: 'Repository info',
                onPressed: () =>
                    RepoInfoDialog.show(context, repo: active.location),
              ),
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
    return Row(
      children: [
        MinimizeWindowButton(colors: colors),
        MaximizeWindowButton(colors: colors),
        CloseWindowButton(colors: closeColors),
      ],
    );
  }
}
