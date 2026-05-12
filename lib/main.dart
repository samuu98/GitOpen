import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import 'application/active_workspace_provider.dart';
import 'application/providers.dart';
import 'application/workspaces/workspace.dart';
import 'ui/bottom_panel/bottom_panel.dart';
import 'ui/commit_graph/commit_graph_panel.dart';
import 'ui/operations/toast_overlay.dart';
import 'ui/shell/repo_selector.dart';
import 'ui/sidebar/sidebar.dart';

final _log = Logger();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();
  await _rehydrate(container);
  _subscribePersistence(container);

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

class GitOpenApp extends StatelessWidget {
  const GitOpenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GitOpen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF1F1F23),
      ),
      home: const Shell(),
    );
  }
}

class Shell extends ConsumerWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activeWorkspaceIdProvider);
    final workspaces = ref.watch(workspaceManagerProvider);
    final active = activeId == null
        ? null
        : workspaces.firstWhereOrNull((w) => w.location.id == activeId);

    return Scaffold(
      backgroundColor: const Color(0xFF1F1F23),
      body: WindowBorder(
        color: const Color(0xFF2C2C31),
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
                        color: const Color(0xFF1F1F23),
                        alignment: Alignment.center,
                        child: active == null
                            ? const Text(
                                'Open a repository to begin.',
                                style: TextStyle(
                                    color: Color(0xFF888892), fontSize: 14),
                              )
                            : Column(
                                children: [
                                  Expanded(child: CommitGraphPanel(repo: active.location)),
                                  SizedBox(
                                    height: 320,
                                    child: BottomPanel(repo: active.location),
                                  ),
                                ],
                              ),
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
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) {
    return WindowTitleBarBox(
      child: Container(
        color: const Color(0xFF2C2C31),
        child: Row(
          children: [
            // Brand: small, on its own draggable surface.
            SizedBox(height: 38, child: MoveWindow(child: const _Brand())),
            // Left drag spacer.
            Expanded(child: MoveWindow()),
            // Repo selector dropdown — non-draggable interactive area.
            const RepoSelector(),
            // Right drag spacer.
            Expanded(child: MoveWindow()),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Color(0xFF4EC9B0),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'GitOpen',
            style: TextStyle(
              color: Color(0xFFD4D4D4),
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
    final colors = WindowButtonColors(
      iconNormal: const Color(0xFFB8B8BC),
      mouseOver: const Color(0xFF34343A),
      mouseDown: const Color(0xFF3D3D44),
      iconMouseOver: const Color(0xFFD4D4D4),
      iconMouseDown: const Color(0xFFD4D4D4),
    );
    final closeColors = WindowButtonColors(
      iconNormal: const Color(0xFFB8B8BC),
      mouseOver: const Color(0xFFC4314B),
      mouseDown: const Color(0xFFA52739),
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
