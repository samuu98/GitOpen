import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shared app shell for every screenshot gallery: turns the debug banner off
/// so it never shows up in a captured PNG (the GitHub gallery leaked it into
/// the public verification screenshots once).
Widget screenshotApp({required ThemeData theme, required Widget home}) =>
    MaterialApp(debugShowCheckedModeBanner: false, theme: theme, home: home);

/// Pumps until [spinner] is on screen and visibly drawn, for a pending-state
/// capture whose spinner runs an endless animation — `pumpAndSettle` would
/// never return for it, and a fixed-duration pump can fire before the frame
/// that first builds the spinner lands.
Future<void> pumpUntilPending(
  WidgetTester tester,
  Finder spinner, {
  Duration step = const Duration(milliseconds: 50),
  int maxPumps = 40,
}) async {
  for (var i = 0; i < maxPumps && spinner.evaluate().isEmpty; i++) {
    await tester.pump(step);
  }
  if (spinner.evaluate().isEmpty) {
    throw TestFailure('Pending spinner never painted: $spinner');
  }
  // An indeterminate indicator starts from a zero-length arc (a dot); let it
  // grow so the capture shows a spinner, not a speck.
  await tester.pump(const Duration(milliseconds: 400));
}

/// Loads Roboto and Material Icons from the Flutter SDK so screenshots show
/// real glyphs instead of the Ahem test font. Without `FLUTTER_ROOT` (set by
/// `flutter test`) the test fonts stay in place.
Future<void> loadAppFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) return;
  final fontDir = Directory(
    '$flutterRoot/bin/cache/artifacts/material_fonts',
  );
  for (final (family, files) in [
    ('Roboto', ['roboto-regular.ttf', 'roboto-medium.ttf']),
    ('MaterialIcons', ['materialicons-regular.otf']),
  ]) {
    final loader = FontLoader(family);
    var added = false;
    for (final name in files) {
      final file = File('${fontDir.path}/$name');
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      added = true;
    }
    if (added) await loader.load();
  }
}

/// Golden comparator that writes every rendered image under
/// `build/pipeline/<dir>/` and never fails: the PNGs are review evidence,
/// the tests assert behaviour separately.
class PipelineScreenshotComparator extends GoldenFileComparator {
  PipelineScreenshotComparator(this.dir);

  final String dir;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    await update(golden, imageBytes);
    return true;
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {
    fileFor(golden.pathSegments.last)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(imageBytes);
  }

  File fileFor(String name) => File('build/pipeline/$dir/$name');
}
