import 'package:flutter/material.dart';

@immutable
final class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg0,
    required this.bg1,
    required this.bg2,
    required this.bg3,
    required this.bg4,
    required this.bg5,
    required this.bgAccent,
    required this.border,
    required this.borderStrong,
    required this.fg0,
    required this.fg1,
    required this.fg2,
    required this.fg3,
    required this.accentCurrent,
    required this.accentTag,
    required this.accentRemote,
    required this.accentWarn,
    required this.accentErr,
    required this.lanePalette,
  });

  factory AppPalette.dark() => const AppPalette(
    bg0: Color(0xFF191A1D),
    bg1: Color(0xFF1E1F23),
    bg2: Color(0xFF25262B),
    bg3: Color(0xFF2D2E34),
    bg4: Color(0xFF373841),
    bg5: Color(0xFF42434D),
    bgAccent: Color(0xFF0B5A84),
    border: Color(0xFF343640),
    borderStrong: Color(0xFF474A56),
    fg0: Color(0xFFE5E7EB),
    fg1: Color(0xFFC4C8D0),
    fg2: Color(0xFFA0A6B2),
    fg3: Color(0xFF808895),
    accentCurrent: Color(0xFF55D6BE),
    accentTag: Color(0xFFE0C46F),
    accentRemote: Color(0xFF6CAEE8),
    accentWarn: Color(0xFFDFA172),
    accentErr: Color(0xFFFF8B7D),
    lanePalette: [
      Color(0xFF55D6BE),
      Color(0xFFE0C46F),
      Color(0xFF6CAEE8),
      Color(0xFFDFA172),
      Color(0xFFC58ED6),
      Color(0xFF8EA7E8),
      Color(0xFFD7A85C),
      Color(0xFFE48797),
    ],
  );

  factory AppPalette.light() => const AppPalette(
    bg0: Color(0xFFFAFAFB),
    bg1: Color(0xFFFFFFFF),
    bg2: Color(0xFFF3F4F6),
    bg3: Color(0xFFE8EAEE),
    bg4: Color(0xFFDDE1E7),
    bg5: Color(0xFFD0D6DF),
    bgAccent: Color(0xFFCBE7FF),
    border: Color(0xFFD4D8E0),
    borderStrong: Color(0xFFB7BFCC),
    fg0: Color(0xFF1F2328),
    fg1: Color(0xFF3F4650),
    fg2: Color(0xFF596270),
    fg3: Color(0xFF6B7483),
    accentCurrent: Color(0xFF0A7E68),
    accentTag: Color(0xFF81600D),
    accentRemote: Color(0xFF1F5F9E),
    accentWarn: Color(0xFF8B4B20),
    accentErr: Color(0xFFA52424),
    lanePalette: [
      Color(0xFF0A7E68),
      Color(0xFF81600D),
      Color(0xFF1F5F9E),
      Color(0xFF8B4B20),
      Color(0xFF72446F),
      Color(0xFF405C8C),
      Color(0xFF79580C),
      Color(0xFF913244),
    ],
  );
  final Color bg0;
  final Color bg1;
  final Color bg2;
  final Color bg3;
  final Color bg4;
  final Color bg5;
  final Color bgAccent;
  final Color border;
  final Color borderStrong;
  final Color fg0;
  final Color fg1;
  final Color fg2;
  final Color fg3;
  final Color accentCurrent;
  final Color accentTag;
  final Color accentRemote;
  final Color accentWarn;
  final Color accentErr;
  final List<Color> lanePalette;

  @override
  AppPalette copyWith({
    Color? bg0,
    Color? bg1,
    Color? bg2,
    Color? bg3,
    Color? bg4,
    Color? bg5,
    Color? bgAccent,
    Color? border,
    Color? borderStrong,
    Color? fg0,
    Color? fg1,
    Color? fg2,
    Color? fg3,
    Color? accentCurrent,
    Color? accentTag,
    Color? accentRemote,
    Color? accentWarn,
    Color? accentErr,
    List<Color>? lanePalette,
  }) {
    return AppPalette(
      bg0: bg0 ?? this.bg0,
      bg1: bg1 ?? this.bg1,
      bg2: bg2 ?? this.bg2,
      bg3: bg3 ?? this.bg3,
      bg4: bg4 ?? this.bg4,
      bg5: bg5 ?? this.bg5,
      bgAccent: bgAccent ?? this.bgAccent,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      fg0: fg0 ?? this.fg0,
      fg1: fg1 ?? this.fg1,
      fg2: fg2 ?? this.fg2,
      fg3: fg3 ?? this.fg3,
      accentCurrent: accentCurrent ?? this.accentCurrent,
      accentTag: accentTag ?? this.accentTag,
      accentRemote: accentRemote ?? this.accentRemote,
      accentWarn: accentWarn ?? this.accentWarn,
      accentErr: accentErr ?? this.accentErr,
      lanePalette: lanePalette ?? this.lanePalette,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bg0: Color.lerp(bg0, other.bg0, t)!,
      bg1: Color.lerp(bg1, other.bg1, t)!,
      bg2: Color.lerp(bg2, other.bg2, t)!,
      bg3: Color.lerp(bg3, other.bg3, t)!,
      bg4: Color.lerp(bg4, other.bg4, t)!,
      bg5: Color.lerp(bg5, other.bg5, t)!,
      bgAccent: Color.lerp(bgAccent, other.bgAccent, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      fg0: Color.lerp(fg0, other.fg0, t)!,
      fg1: Color.lerp(fg1, other.fg1, t)!,
      fg2: Color.lerp(fg2, other.fg2, t)!,
      fg3: Color.lerp(fg3, other.fg3, t)!,
      accentCurrent: Color.lerp(accentCurrent, other.accentCurrent, t)!,
      accentTag: Color.lerp(accentTag, other.accentTag, t)!,
      accentRemote: Color.lerp(accentRemote, other.accentRemote, t)!,
      accentWarn: Color.lerp(accentWarn, other.accentWarn, t)!,
      accentErr: Color.lerp(accentErr, other.accentErr, t)!,
      lanePalette: lanePalette, // not lerped — palette swap is discrete
    );
  }

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>()!;
}
