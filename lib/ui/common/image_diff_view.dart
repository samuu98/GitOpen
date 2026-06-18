import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/diff/image_preview.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/files/file_content.dart';
import 'package:gitopen/domain/files/file_revision.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

final _fileBytesProvider = FutureProvider.family
    .autoDispose<
      FileContent,
      ({RepoLocation repo, FileRevision revision, String path})
    >(
      (ref, key) => ref
          .watch(gitReadOperationsProvider)
          .getFileBytes(key.repo, key.revision, key.path),
    );

/// Old/new side-by-side preview for a binary image file: checkerboard
/// backdrop, byte-size + pixel-dimension labels, explicit states for a
/// missing side and for files over the preview size cap.
class ImageDiffView extends StatelessWidget {
  const ImageDiffView({
    required this.repo,
    required this.oldPath,
    required this.newPath,
    required this.oldRevision,
    required this.newRevision,
    super.key,
  });
  final RepoLocation repo;
  final String oldPath;
  final String newPath;
  final FileRevision oldRevision;
  final FileRevision newRevision;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _ImageSide(
              label: 'Old',
              repo: repo,
              path: oldPath,
              revision: oldRevision,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ImageSide(
              label: 'New',
              repo: repo,
              path: newPath,
              revision: newRevision,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageSide extends ConsumerWidget {
  const _ImageSide({
    required this.label,
    required this.repo,
    required this.path,
    required this.revision,
  });
  final String label;
  final RepoLocation repo;
  final String path;
  final FileRevision revision;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async = ref.watch(
      _fileBytesProvider((repo: repo, revision: revision, path: path)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: palette.fg2,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => Text(
            'Error: $e',
            style: TextStyle(color: palette.accentErr, fontSize: 11.5),
          ),
          data: (content) => _body(context, content),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, FileContent content) {
    final palette = AppPalette.of(context);
    if (!content.exists) {
      return Text(
        'Not present',
        style: TextStyle(
          color: palette.fg3,
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    if (content.tooLarge) {
      return Text(
        'Too large to preview (${formatBytes(content.sizeBytes)})',
        style: TextStyle(
          color: palette.fg2,
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    final bytes = content.bytes!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(4),
          ),
          clipBehavior: Clip.antiAlias,
          child: CustomPaint(
            painter: _CheckerboardPainter(
              light: palette.bg2,
              dark: palette.bg4,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              formatBytes(content.sizeBytes),
              style: TextStyle(color: palette.fg2, fontSize: 11),
            ),
            const SizedBox(width: 8),
            _DimensionsLabel(bytes: bytes),
          ],
        ),
      ],
    );
  }
}

/// 'W × H px', resolved by decoding the image header asynchronously.
/// Renders nothing until (or unless) the decode succeeds.
class _DimensionsLabel extends StatelessWidget {
  const _DimensionsLabel({required this.bytes});
  final Uint8List bytes;

  Future<({int width, int height})> _decode() {
    final completer = Completer<({int width, int height})>();
    ui.decodeImageFromList(bytes, (image) {
      completer.complete((width: image.width, height: image.height));
      image.dispose();
    });
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return FutureBuilder(
      future: _decode(),
      builder: (context, snapshot) {
        final size = snapshot.data;
        if (size == null) return const SizedBox.shrink();
        return Text(
          '${size.width} × ${size.height} px',
          style: TextStyle(color: palette.fg2, fontSize: 11),
        );
      },
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  const _CheckerboardPainter({required this.light, required this.dark});
  final Color light;
  final Color dark;

  static const double _square = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final lightPaint = Paint()..color = light;
    final darkPaint = Paint()..color = dark;
    canvas.drawRect(Offset.zero & size, lightPaint);
    for (var y = 0; y * _square < size.height; y++) {
      for (var x = y.isEven ? 1 : 0; x * _square < size.width; x += 2) {
        canvas.drawRect(
          Rect.fromLTWH(x * _square, y * _square, _square, _square),
          darkPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerboardPainter oldDelegate) =>
      light != oldDelegate.light || dark != oldDelegate.dark;
}
