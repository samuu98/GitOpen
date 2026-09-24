import 'dart:io';

import 'package:flutter/services.dart';

import '../../_helpers/screenshot.dart';

Future<void> loadWorkingCopyFonts() async {
  await loadAppFonts();
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final file = File(
    '$root/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
  );
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  await (FontLoader(
    'monospace',
  )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}
