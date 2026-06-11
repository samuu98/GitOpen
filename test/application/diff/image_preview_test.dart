import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/diff/image_preview.dart';

void main() {
  group('isImagePath', () {
    test('recognises the supported extensions case-insensitively', () {
      for (final p in [
        'a.png', 'b.jpg', 'c.JPEG', 'd.gif', 'e.webp', 'dir/f.BMP',
      ]) {
        expect(isImagePath(p), isTrue, reason: p);
      }
    });

    test('rejects non-image and extension-less paths', () {
      expect(isImagePath('a.txt'), isFalse);
      expect(isImagePath('archive.png.zip'), isFalse);
      expect(isImagePath('Makefile'), isFalse);
    });
  });

  group('formatBytes', () {
    test('formats B / KB / MB / GB', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(999), '999 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(20 * 1024 * 1024), '20.0 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });
  });
}
