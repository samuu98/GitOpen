import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/active_workspace_provider.dart';
import 'application/providers.dart';
import 'ui/shell/tab_bar.dart';
import 'ui/sidebar/sidebar.dart';

void main() {
  runApp(const ProviderScope(child: GitOpenApp()));

  doWhenWindowReady(() {
    const initialSize = Size(1400, 900);
    appWindow.minSize = const Size(800, 500);
    appWindow.size = initialSize;
    appWindow.alignment = Alignment.center;
    appWindow.title = 'GitOpen';
    appWindow.show();
  });
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
        child: Column(
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
                          : Text(
                              'Repository: ${active.location.displayName}\n(commit graph coming in Phase H)',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Color(0xFFB8B8BC), fontSize: 13),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
            const _Brand(),
            const SizedBox(width: 8),
            const Expanded(child: TabsBar()),
            // A 16-px wide drag handle between tabs and controls
            SizedBox(width: 16, height: 38, child: MoveWindow()),
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
      child: MoveWindow(
        child: Row(
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
