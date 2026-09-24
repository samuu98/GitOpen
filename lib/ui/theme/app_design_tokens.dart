import 'package:flutter/material.dart';

@immutable
final class AppSpacing extends ThemeExtension<AppSpacing> {
  const AppSpacing({
    required this.xxs,
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.xxl,
    this.compactControlHeight = 28,
    this.regularControlHeight = 38,
    this.graphRowHeight = 26,
    this.listRowHeight = 30,
    this.menuRowHeight = 30,
    this.statusIconSize = 11,
    this.compactIconSize = 13,
    this.regularIconSize = 14,
  });

  const factory AppSpacing.desktop() = AppSpacing._desktop;

  const AppSpacing._desktop()
    : xxs = 4,
      xs = 6,
      sm = 8,
      md = 12,
      lg = 16,
      xl = 24,
      xxl = 32,
      compactControlHeight = 28,
      regularControlHeight = 38,
      graphRowHeight = 26,
      listRowHeight = 30,
      menuRowHeight = 30,
      statusIconSize = 11,
      compactIconSize = 13,
      regularIconSize = 14;

  final double xxs;
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;
  final double compactControlHeight;
  final double regularControlHeight;
  final double graphRowHeight;
  final double listRowHeight;
  final double menuRowHeight;
  final double statusIconSize;
  final double compactIconSize;
  final double regularIconSize;

  EdgeInsets get panel => EdgeInsets.all(md);
  EdgeInsets get row => EdgeInsets.symmetric(horizontal: md, vertical: sm);
  EdgeInsets get compactRow => EdgeInsets.symmetric(
    horizontal: sm,
    vertical: xxs,
  );

  @override
  AppSpacing copyWith({
    double? xxs,
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
    double? compactControlHeight,
    double? regularControlHeight,
    double? graphRowHeight,
    double? listRowHeight,
    double? menuRowHeight,
    double? statusIconSize,
    double? compactIconSize,
    double? regularIconSize,
  }) {
    return AppSpacing(
      xxs: xxs ?? this.xxs,
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      xxl: xxl ?? this.xxl,
      compactControlHeight: compactControlHeight ?? this.compactControlHeight,
      regularControlHeight: regularControlHeight ?? this.regularControlHeight,
      graphRowHeight: graphRowHeight ?? this.graphRowHeight,
      listRowHeight: listRowHeight ?? this.listRowHeight,
      menuRowHeight: menuRowHeight ?? this.menuRowHeight,
      statusIconSize: statusIconSize ?? this.statusIconSize,
      compactIconSize: compactIconSize ?? this.compactIconSize,
      regularIconSize: regularIconSize ?? this.regularIconSize,
    );
  }

  @override
  AppSpacing lerp(ThemeExtension<AppSpacing>? other, double t) {
    if (other is! AppSpacing) return this;
    return AppSpacing(
      xxs: _lerpDouble(xxs, other.xxs, t),
      xs: _lerpDouble(xs, other.xs, t),
      sm: _lerpDouble(sm, other.sm, t),
      md: _lerpDouble(md, other.md, t),
      lg: _lerpDouble(lg, other.lg, t),
      xl: _lerpDouble(xl, other.xl, t),
      xxl: _lerpDouble(xxl, other.xxl, t),
      compactControlHeight: _lerpDouble(
        compactControlHeight,
        other.compactControlHeight,
        t,
      ),
      regularControlHeight: _lerpDouble(
        regularControlHeight,
        other.regularControlHeight,
        t,
      ),
      graphRowHeight: _lerpDouble(graphRowHeight, other.graphRowHeight, t),
      listRowHeight: _lerpDouble(listRowHeight, other.listRowHeight, t),
      menuRowHeight: _lerpDouble(menuRowHeight, other.menuRowHeight, t),
      statusIconSize: _lerpDouble(statusIconSize, other.statusIconSize, t),
      compactIconSize: _lerpDouble(compactIconSize, other.compactIconSize, t),
      regularIconSize: _lerpDouble(regularIconSize, other.regularIconSize, t),
    );
  }

  static AppSpacing of(BuildContext context) =>
      Theme.of(context).extension<AppSpacing>() ?? _defaultSpacing;
}

@immutable
final class AppRadii extends ThemeExtension<AppRadii> {
  const AppRadii({
    required this.control,
    required this.row,
    required this.panel,
    required this.dialog,
    required this.pill,
  });

  const factory AppRadii.desktop() = AppRadii._desktop;

  const AppRadii._desktop()
    : control = 4,
      row = 4,
      panel = 6,
      dialog = 8,
      pill = 999;

  final double control;
  final double row;
  final double panel;
  final double dialog;
  final double pill;

  BorderRadius get controlRadius => BorderRadius.circular(control);
  BorderRadius get rowRadius => BorderRadius.circular(row);
  BorderRadius get panelRadius => BorderRadius.circular(panel);
  BorderRadius get dialogRadius => BorderRadius.circular(dialog);
  BorderRadius get pillRadius => BorderRadius.circular(pill);

  @override
  AppRadii copyWith({
    double? control,
    double? row,
    double? panel,
    double? dialog,
    double? pill,
  }) {
    return AppRadii(
      control: control ?? this.control,
      row: row ?? this.row,
      panel: panel ?? this.panel,
      dialog: dialog ?? this.dialog,
      pill: pill ?? this.pill,
    );
  }

  @override
  AppRadii lerp(ThemeExtension<AppRadii>? other, double t) {
    if (other is! AppRadii) return this;
    return AppRadii(
      control: _lerpDouble(control, other.control, t),
      row: _lerpDouble(row, other.row, t),
      panel: _lerpDouble(panel, other.panel, t),
      dialog: _lerpDouble(dialog, other.dialog, t),
      pill: _lerpDouble(pill, other.pill, t),
    );
  }

  static AppRadii of(BuildContext context) =>
      Theme.of(context).extension<AppRadii>() ?? _defaultRadii;
}

@immutable
final class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
    required this.caption,
    required this.captionStrong,
    required this.body,
    required this.bodyStrong,
    required this.title,
    required this.mono,
    required this.monoSmall,
  });

  const factory AppTypography.desktop() = AppTypography._desktop;

  const AppTypography._desktop()
    : caption = const TextStyle(fontSize: 11.5),
      captionStrong = const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
      ),
      body = const TextStyle(fontSize: 12.5),
      bodyStrong = const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
      title = const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      mono = const TextStyle(fontSize: 12, fontFamily: 'monospace'),
      monoSmall = const TextStyle(fontSize: 11, fontFamily: 'monospace');

  final TextStyle caption;
  final TextStyle captionStrong;
  final TextStyle body;
  final TextStyle bodyStrong;
  final TextStyle title;
  final TextStyle mono;
  final TextStyle monoSmall;

  @override
  AppTypography copyWith({
    TextStyle? caption,
    TextStyle? captionStrong,
    TextStyle? body,
    TextStyle? bodyStrong,
    TextStyle? title,
    TextStyle? mono,
    TextStyle? monoSmall,
  }) {
    return AppTypography(
      caption: caption ?? this.caption,
      captionStrong: captionStrong ?? this.captionStrong,
      body: body ?? this.body,
      bodyStrong: bodyStrong ?? this.bodyStrong,
      title: title ?? this.title,
      mono: mono ?? this.mono,
      monoSmall: monoSmall ?? this.monoSmall,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      caption: TextStyle.lerp(caption, other.caption, t)!,
      captionStrong: TextStyle.lerp(captionStrong, other.captionStrong, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      bodyStrong: TextStyle.lerp(bodyStrong, other.bodyStrong, t)!,
      title: TextStyle.lerp(title, other.title, t)!,
      mono: TextStyle.lerp(mono, other.mono, t)!,
      monoSmall: TextStyle.lerp(monoSmall, other.monoSmall, t)!,
    );
  }

  static AppTypography of(BuildContext context) =>
      Theme.of(context).extension<AppTypography>() ?? _defaultTypography;
}

@immutable
final class AppMotion extends ThemeExtension<AppMotion> {
  const AppMotion({
    required this.fast,
    required this.normal,
    required this.slow,
    required this.curve,
    required this.indicatorDelay,
    required this.indicatorMinimum,
  });

  const factory AppMotion.standard() = AppMotion._standard;

  const AppMotion._standard()
    : fast = const Duration(milliseconds: 120),
      normal = const Duration(milliseconds: 160),
      slow = const Duration(milliseconds: 200),
      curve = Curves.easeOutCubic,
      indicatorDelay = const Duration(milliseconds: 150),
      indicatorMinimum = const Duration(milliseconds: 400);

  final Duration fast;
  final Duration normal;
  final Duration slow;
  final Curve curve;

  /// How long an action may run before its pending indicator appears. Anything
  /// that finishes sooner shows nothing at all instead of flashing a spinner.
  final Duration indicatorDelay;

  /// How long a pending indicator stays once it is shown, so a fast refresh
  /// cannot make it blink out the frame after it appeared.
  final Duration indicatorMinimum;

  @override
  AppMotion copyWith({
    Duration? fast,
    Duration? normal,
    Duration? slow,
    Curve? curve,
    Duration? indicatorDelay,
    Duration? indicatorMinimum,
  }) {
    return AppMotion(
      fast: fast ?? this.fast,
      normal: normal ?? this.normal,
      slow: slow ?? this.slow,
      curve: curve ?? this.curve,
      indicatorDelay: indicatorDelay ?? this.indicatorDelay,
      indicatorMinimum: indicatorMinimum ?? this.indicatorMinimum,
    );
  }

  @override
  AppMotion lerp(ThemeExtension<AppMotion>? other, double t) {
    if (other is! AppMotion) return this;
    return AppMotion(
      fast: _lerpDuration(fast, other.fast, t),
      normal: _lerpDuration(normal, other.normal, t),
      slow: _lerpDuration(slow, other.slow, t),
      curve: t < 0.5 ? curve : other.curve,
      indicatorDelay: _lerpDuration(
        indicatorDelay,
        other.indicatorDelay,
        t,
      ),
      indicatorMinimum: _lerpDuration(
        indicatorMinimum,
        other.indicatorMinimum,
        t,
      ),
    );
  }

  static AppMotion of(BuildContext context) =>
      Theme.of(context).extension<AppMotion>() ?? _defaultMotion;
}

/// Canonical desktop defaults, used by the `of(context)` accessors when a
/// theme has not registered the extension (e.g. lightweight widget tests).
const AppSpacing _defaultSpacing = AppSpacing.desktop();
const AppRadii _defaultRadii = AppRadii.desktop();
const AppTypography _defaultTypography = AppTypography.desktop();
const AppMotion _defaultMotion = AppMotion.standard();

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

Duration _lerpDuration(Duration a, Duration b, double t) {
  return Duration(
    microseconds: _lerpDouble(
      a.inMicroseconds.toDouble(),
      b.inMicroseconds.toDouble(),
      t,
    ).round(),
  );
}
