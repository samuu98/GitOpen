import 'package:flutter/material.dart';

/// Semantic text scale for the app, exposed as a [ThemeExtension] alongside
/// [AppPalette]. Styles are colorless — apply `copyWith(color: …)` at the
/// call site so the palette stays the single source of color truth.
///
/// Built from the user's `fontFamily` / `fontSize` settings so the whole UI
/// follows them; `fontSize` is the base body size (default 12).
@immutable
final class AppTypography extends ThemeExtension<AppTypography> {
  /// Dialog/page titles.
  final TextStyle heading;

  /// Panel titles and emphasized rows.
  final TextStyle title;

  /// Default UI text (menus, rows, dialogs).
  final TextStyle body;

  /// Secondary text (subtitles, metadata, status bar).
  final TextStyle bodySmall;

  /// Uppercase section labels (sidebar headers).
  final TextStyle label;

  /// Code/SHA/path text.
  final TextStyle mono;

  /// Smaller mono variant (inline metadata, diff gutters).
  final TextStyle monoSmall;

  const AppTypography({
    required this.heading,
    required this.title,
    required this.body,
    required this.bodySmall,
    required this.label,
    required this.mono,
    required this.monoSmall,
  });

  /// Monospace stack that resolves on Windows, macOS and Linux.
  static const List<String> monoFallback = [
    'Consolas', 'Menlo', 'DejaVu Sans Mono', 'monospace',
  ];

  factory AppTypography.fromSettings({String? fontFamily, int baseSize = 12}) {
    final base = baseSize.toDouble();
    TextStyle ui(double size, [FontWeight? weight, double? spacing]) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: spacing,
          height: 1.35,
        );
    TextStyle mono(double size, [FontWeight? weight]) => TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: monoFallback,
          fontSize: size,
          fontWeight: weight,
          height: 1.35,
        );
    return AppTypography(
      heading: ui(base + 2.5, FontWeight.w600),
      title: ui(base + 1, FontWeight.w600),
      body: ui(base + 0.5),
      bodySmall: ui(base - 0.5),
      label: ui(base - 1.5, FontWeight.w600, 0.8),
      mono: mono(base + 0.5),
      monoSmall: mono(base - 0.5),
    );
  }

  @override
  AppTypography copyWith({
    TextStyle? heading,
    TextStyle? title,
    TextStyle? body,
    TextStyle? bodySmall,
    TextStyle? label,
    TextStyle? mono,
    TextStyle? monoSmall,
  }) {
    return AppTypography(
      heading: heading ?? this.heading,
      title: title ?? this.title,
      body: body ?? this.body,
      bodySmall: bodySmall ?? this.bodySmall,
      label: label ?? this.label,
      mono: mono ?? this.mono,
      monoSmall: monoSmall ?? this.monoSmall,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      heading: TextStyle.lerp(heading, other.heading, t)!,
      title: TextStyle.lerp(title, other.title, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      bodySmall: TextStyle.lerp(bodySmall, other.bodySmall, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
      mono: TextStyle.lerp(mono, other.mono, t)!,
      monoSmall: TextStyle.lerp(monoSmall, other.monoSmall, t)!,
    );
  }

  static AppTypography of(BuildContext context) =>
      Theme.of(context).extension<AppTypography>()!;
}
