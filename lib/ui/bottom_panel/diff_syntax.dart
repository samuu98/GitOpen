import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show Node, highlight;

/// Syntax-highlighting helpers for the diff views.
///
/// Everything here is additive and defensive: when a language is unknown or
/// the highlighter throws, callers receive a single plain [TextSpan] that
/// renders identically to the previous plain-monospace behaviour.

/// Maps a file [path] to a `highlight` package language id, or `null` when the
/// extension is unknown (in which case callers fall back to plain text).
///
/// Detection is purely extension-based and case-insensitive. Files without a
/// real extension (including dotfiles such as `.gitignore`) return `null`.
String? languageForPath(String path) {
  if (path.isEmpty) return null;

  // Take the segment after the last path separator (handles both / and \).
  var name = path;
  final slash = name.lastIndexOf('/');
  final backslash = name.lastIndexOf(r'\');
  final sep = slash > backslash ? slash : backslash;
  if (sep >= 0) name = name.substring(sep + 1);

  final dot = name.lastIndexOf('.');
  // No dot, or a leading dot only (dotfile with no further extension).
  if (dot <= 0) return null;

  final ext = name.substring(dot + 1).toLowerCase();
  return _extensionToLanguage[ext];
}

/// Extension (lower-case, without the dot) → `highlight` language id.
const Map<String, String> _extensionToLanguage = {
  'dart': 'dart',
  'yaml': 'yaml',
  'yml': 'yaml',
  'json': 'json',
  'js': 'javascript',
  'mjs': 'javascript',
  'cjs': 'javascript',
  'jsx': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'py': 'python',
  'pyw': 'python',
  'java': 'java',
  'c': 'c',
  'h': 'c',
  'cpp': 'cpp',
  'cc': 'cpp',
  'cxx': 'cpp',
  'hpp': 'cpp',
  'hh': 'cpp',
  'cs': 'cs',
  'go': 'go',
  'rs': 'rust',
  'sh': 'bash',
  'bash': 'bash',
  'zsh': 'bash',
  'html': 'xml',
  'htm': 'xml',
  'xhtml': 'xml',
  'xml': 'xml',
  'svg': 'xml',
  'css': 'css',
  'scss': 'scss',
  'less': 'less',
  'md': 'markdown',
  'markdown': 'markdown',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'swift': 'swift',
  'rb': 'ruby',
  'php': 'php',
  'sql': 'sql',
  'go_mod': 'go',
  'lua': 'lua',
  'pl': 'perl',
  'pm': 'perl',
  'r': 'r',
  'scala': 'scala',
  'groovy': 'groovy',
  'gradle': 'groovy',
  'vue': 'vue',
  'ini': 'ini',
  'toml': 'ini',
  'dockerfile': 'dockerfile',
  'makefile': 'makefile',
  'mk': 'makefile',
  'ps1': 'powershell',
  'psm1': 'powershell',
  'bat': 'dos',
  'cmd': 'dos',
  'm': 'objectivec',
  'mm': 'objectivec',
  'ex': 'elixir',
  'exs': 'elixir',
  'erl': 'erlang',
  'hs': 'haskell',
  'clj': 'clojure',
  'cljs': 'clojure',
  'fs': 'fsharp',
  'fsx': 'fsharp',
  'jl': 'julia',
  'tex': 'tex',
};

/// Dark-theme token colours keyed by `highlight` className.
///
/// Loosely follows the VS Code dark palette (the same family the app's
/// `AppPalette.dark` uses) so token colours sit comfortably on the diff's
/// tinted add/delete backgrounds. Unknown classNames inherit the base colour.
const Map<String, Color> _darkTokenColors = {
  'keyword': Color(0xFF569CD6),
  'built_in': Color(0xFF4EC9B0),
  'type': Color(0xFF4EC9B0),
  'class': Color(0xFF4EC9B0),
  'title': Color(0xFFDCDCAA),
  'title.function': Color(0xFFDCDCAA),
  'function': Color(0xFFDCDCAA),
  'literal': Color(0xFF569CD6),
  'number': Color(0xFFB5CEA8),
  'string': Color(0xFFCE9178),
  'subst': Color(0xFFD4D4D4),
  'symbol': Color(0xFFD4D4D4),
  'regexp': Color(0xFFD16969),
  'comment': Color(0xFF6A9955),
  'doctag': Color(0xFF6A9955),
  'meta': Color(0xFF9CDCFE),
  'meta-keyword': Color(0xFF569CD6),
  'meta-string': Color(0xFFCE9178),
  'attr': Color(0xFF9CDCFE),
  'attribute': Color(0xFF9CDCFE),
  'name': Color(0xFF569CD6),
  'tag': Color(0xFF808080),
  'builtin-name': Color(0xFF4EC9B0),
  'selector-tag': Color(0xFFD7BA7D),
  'selector-id': Color(0xFFD7BA7D),
  'selector-class': Color(0xFFD7BA7D),
  'selector-attr': Color(0xFFD7BA7D),
  'selector-pseudo': Color(0xFFD7BA7D),
  'variable': Color(0xFF9CDCFE),
  'variable.language': Color(0xFF569CD6),
  'template-variable': Color(0xFF9CDCFE),
  'params': Color(0xFF9CDCFE),
  'property': Color(0xFF9CDCFE),
  'section': Color(0xFFDCDCAA),
  'bullet': Color(0xFFD7BA7D),
  'quote': Color(0xFF6A9955),
  'link': Color(0xFF569CD6),
  'emphasis': Color(0xFFCE9178),
  'strong': Color(0xFFCE9178),
  'addition': Color(0xFFB5CEA8),
  'deletion': Color(0xFFD16969),
};

/// Builds the [TextSpan]s for a single diff line of source [code].
///
/// When [language] is `null`, unrecognised, or the highlighter throws, a
/// single plain [TextSpan] using [baseColor] is returned so rendering is
/// byte-for-byte identical to the previous plain-monospace output. The
/// concatenation of every returned span's text always equals [code].
List<TextSpan> buildHighlightedSpans(
  String code,
  String? language, {
  required Color baseColor,
}) {
  if (language == null || code.isEmpty) {
    return [TextSpan(text: code, style: TextStyle(color: baseColor))];
  }

  try {
    final result = highlight.parse(code, language: language);
    final nodes = result.nodes;
    if (nodes == null || nodes.isEmpty) {
      return [TextSpan(text: code, style: TextStyle(color: baseColor))];
    }

    final spans = <TextSpan>[];
    for (final node in nodes) {
      _appendNode(node, baseColor, spans);
    }
    if (spans.isEmpty) {
      return [TextSpan(text: code, style: TextStyle(color: baseColor))];
    }
    return spans;
  } on Object catch (_) {
    // Highlighter failed (unknown language id, parser edge case, …) — keep
    // the existing plain rendering rather than dropping the line.
    return [TextSpan(text: code, style: TextStyle(color: baseColor))];
  }
}

/// Recursively flattens a highlight [node] into flat [TextSpan]s, resolving
/// each leaf's colour from its (or its ancestors') className.
void _appendNode(Node node, Color baseColor, List<TextSpan> out) {
  final color = _darkTokenColors[node.className] ?? baseColor;

  final value = node.value;
  if (value != null && value.isNotEmpty) {
    out.add(TextSpan(text: value, style: TextStyle(color: color)));
  }

  final children = node.children;
  if (children != null) {
    for (final child in children) {
      // A child without its own className inherits this node's colour.
      _appendNode(child, color, out);
    }
  }
}
