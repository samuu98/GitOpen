import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/bottom_panel/diff_syntax.dart';

void main() {
  group('languageForPath', () {
    test('maps common extensions to highlight language ids', () {
      expect(languageForPath('lib/main.dart'), 'dart');
      expect(languageForPath('pubspec.yaml'), 'yaml');
      expect(languageForPath('config.yml'), 'yaml');
      expect(languageForPath('data.json'), 'json');
      expect(languageForPath('app.js'), 'javascript');
      expect(languageForPath('app.ts'), 'typescript');
      expect(languageForPath('script.py'), 'python');
      expect(languageForPath('Main.java'), 'java');
      expect(languageForPath('main.c'), 'c');
      expect(languageForPath('main.cpp'), 'cpp');
      expect(languageForPath('Program.cs'), 'cs');
      expect(languageForPath('server.go'), 'go');
      expect(languageForPath('lib.rs'), 'rust');
      expect(languageForPath('build.sh'), 'bash');
      expect(languageForPath('index.html'), 'xml');
      expect(languageForPath('styles.css'), 'css');
      expect(languageForPath('README.md'), 'markdown');
      expect(languageForPath('pom.xml'), 'xml');
      expect(languageForPath('App.kt'), 'kotlin');
      expect(languageForPath('View.swift'), 'swift');
      expect(languageForPath('app.rb'), 'ruby');
      expect(languageForPath('index.php'), 'php');
      expect(languageForPath('query.sql'), 'sql');
    });

    test('returns null for unknown extensions', () {
      expect(languageForPath('mystery.qqq'), isNull);
      expect(languageForPath('archive.bin'), isNull);
    });

    test('returns null when there is no extension', () {
      expect(languageForPath('Makefile'), isNull);
      expect(languageForPath('LICENSE'), isNull);
    });

    test('is case-insensitive on the extension', () {
      expect(languageForPath('Main.DART'), 'dart');
      expect(languageForPath('CONFIG.YAML'), 'yaml');
      expect(languageForPath('Data.JSON'), 'json');
    });

    test('handles full and nested paths', () {
      expect(languageForPath('a/b/c/widget.dart'), 'dart');
      expect(languageForPath(r'a\b\c\widget.dart'), 'dart');
      expect(languageForPath('src/deep/nested/styles.scss'), 'scss');
    });

    test('handles dotfiles with a known extension', () {
      // ".gitignore" is treated as having no extension (leading dot only).
      expect(languageForPath('.gitignore'), isNull);
      // A dotfile that nonetheless carries a real extension still maps.
      expect(languageForPath('.eslintrc.json'), 'json');
    });

    test('handles paths with multiple dots', () {
      expect(languageForPath('app.module.ts'), 'typescript');
      expect(languageForPath('a.b.c.py'), 'python');
    });

    test('returns null for empty path', () {
      expect(languageForPath(''), isNull);
    });
  });

  group('buildHighlightedSpans', () {
    test('returns a single plain span when language is null', () {
      final spans = buildHighlightedSpans(
        'some plain text',
        null,
        baseColor: const Color(0xFFFFFFFF),
      );
      expect(spans.length, 1);
      expect(spans.first.text, 'some plain text');
    });

    test('falls back to a single plain span on an unknown language', () {
      final spans = buildHighlightedSpans(
        'void main() {}',
        'definitely-not-a-language',
        baseColor: const Color(0xFFFFFFFF),
      );
      expect(spans.length, 1);
      expect(spans.first.text, 'void main() {}');
    });

    test('reconstructs the original text from highlighted spans', () {
      final spans = buildHighlightedSpans(
        "final x = 'hi';",
        'dart',
        baseColor: const Color(0xFFFFFFFF),
      );
      final reconstructed = spans.map((s) => s.text ?? '').join();
      expect(reconstructed, "final x = 'hi';");
    });

    test('produces more than one span for highlightable code', () {
      final spans = buildHighlightedSpans(
        "final greeting = 'hello world';",
        'dart',
        baseColor: const Color(0xFFFFFFFF),
      );
      expect(spans.length, greaterThan(1));
    });

    test('returns a single plain span for empty content', () {
      final spans = buildHighlightedSpans(
        '',
        'dart',
        baseColor: const Color(0xFFFFFFFF),
      );
      expect(spans.length, 1);
      expect(spans.first.text, '');
    });

    test('preserves content exactly even when parsing throws', () {
      // Pass an empty-but-recognised language id edge case; reconstruction
      // must always equal the input.
      final spans = buildHighlightedSpans(
        'a + b',
        'json',
        baseColor: const Color(0xFFFFFFFF),
      );
      final reconstructed = spans.map((s) => s.text ?? '').join();
      expect(reconstructed, 'a + b');
    });
  });
}
