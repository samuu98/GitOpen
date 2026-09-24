import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/common/app_animated_row.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/common/app_icon_button.dart';
import 'package:gitopen/ui/common/app_interactive_surface.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

import '../../_helpers/screenshot.dart';

const _states = [
  'default',
  'hover',
  'pressed',
  'focus',
  'disabled',
  'selected',
];
const _controls = ['Icon', 'Button', 'Row', 'Context item', 'Menu button'];
const _densities = ['compact', 'regular'];
const _cellWidth = 246.0;
const _rowHeight = 56.0;
const _labelWidth = 126.0;
const _headerHeight = 36.0;

Set<WidgetState> _visualStates(String state) => switch (state) {
  'hover' => {WidgetState.hovered},
  'pressed' => {WidgetState.pressed},
  'focus' => {WidgetState.focused},
  _ => const {},
};

Widget _control(int kind, bool compact, String state) {
  final action = state == 'disabled' ? null : () {};
  final selected = state == 'selected';
  final visualStates = _visualStates(state);
  return switch (kind) {
    0 => AppIconButton(
      icon: Icons.star_border,
      tooltip: 'Star repository',
      onPressed: action,
      selected: selected,
      size: compact ? 28 : 38,
      iconSize: compact ? 13 : 14,
      visualStates: visualStates,
    ),
    1 => AppButton.secondary(
      label: 'Open repository',
      onPressed: action,
      selected: selected,
      compact: compact,
      visualStates: visualStates,
    ),
    2 => AppAnimatedRow(
      selected: selected,
      onTap: action,
      semanticLabel: 'Repository row',
      height: compact ? 26 : 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      visualStates: visualStates,
      child: const Text('Repository row'),
    ),
    3 => AppContextMenuRow(
      label: 'Open in terminal',
      icon: Icons.terminal,
      danger: false,
      enabled: action != null,
      selected: selected,
      visualStates: visualStates,
    ),
    _ => AppMenuButton(
      label: 'Open in terminal',
      icon: Icons.terminal,
      onPressed: action,
      selected: selected,
      compact: compact,
      visualStates: visualStates,
    ),
  };
}

Widget _gallery(AppPalette palette, Key key) {
  final width = _labelWidth + _cellWidth * _states.length;
  final height =
      _headerHeight + _rowHeight * _controls.length * _densities.length;
  return MaterialApp(
    theme: ThemeData(
      fontFamily: 'Roboto',
      brightness: palette.bg0.computeLuminance() < 0.5
          ? Brightness.dark
          : Brightness.light,
      extensions: [
        palette,
        const AppSpacing.desktop(),
        const AppRadii.desktop(),
        const AppTypography.desktop(),
        const AppMotion.standard(),
      ],
    ),
    home: Scaffold(
      backgroundColor: palette.bg0,
      body: RepaintBoundary(
        key: key,
        child: ColoredBox(
          color: palette.bg0,
          child: SizedBox(
            width: width,
            height: height,
            child: Column(
              children: [
                SizedBox(
                  height: _headerHeight,
                  child: Row(
                    children: [
                      const SizedBox(width: _labelWidth),
                      for (final state in _states)
                        SizedBox(
                          width: _cellWidth,
                          child: Text(
                            state,
                            style: TextStyle(color: palette.fg0),
                          ),
                        ),
                    ],
                  ),
                ),
                for (final density in _densities)
                  for (var kind = 0; kind < _controls.length; kind++)
                    SizedBox(
                      height: _rowHeight,
                      child: Row(
                        children: [
                          SizedBox(
                            width: _labelWidth,
                            child: Text(
                              '$density ${_controls[kind]}',
                              style: TextStyle(color: palette.fg0),
                            ),
                          ),
                          for (final state in _states)
                            ColoredBox(
                              color: palette.bg1,
                              child: SizedBox(
                                width: _cellWidth,
                                height: _rowHeight,
                                child: Center(
                                  child: _control(
                                    kind,
                                    density == 'compact',
                                    state,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

final _screenshots = PipelineScreenshotComparator('ux-l1-interaction');

void main() {
  setUpAll(loadAppFonts);
  for (final (name, palette) in [
    ('dark', AppPalette.dark()),
    ('light', AppPalette.light()),
  ]) {
    testWidgets('renders $name interaction gallery', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1610, 610));
      final previousComparator = goldenFileComparator;
      goldenFileComparator = _screenshots;
      addTearDown(() => goldenFileComparator = previousComparator);
      final key = GlobalKey();
      await tester.pumpWidget(_gallery(palette, key));
      await tester.pump(const Duration(milliseconds: 180));

      expect(find.byType(AppIconButton), findsNWidgets(12));
      expect(find.byType(AppButton), findsNWidgets(12));
      expect(find.byType(AppAnimatedRow), findsNWidgets(12));
      expect(find.byType(AppMenuButton), findsNWidgets(12));
      expect(find.byType(AppContextMenuRow), findsNWidgets(12));
      expect(find.byType(AppInteractiveSurface), findsNWidgets(36));

      await expectLater(
        find.byKey(key),
        matchesGoldenFile('interaction_gallery_$name.png'),
      );
      expect(
        _screenshots.fileFor('interaction_gallery_$name.png').existsSync(),
        isTrue,
      );
    });
  }
}
