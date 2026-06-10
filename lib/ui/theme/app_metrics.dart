/// Shared layout constants — spacing, radii, icon sizes, durations.
/// Keeps paddings and sizes consistent across surfaces instead of ad-hoc
/// numbers scattered per widget.
library;

import 'package:flutter/widgets.dart';

abstract final class AppMetrics {
  // Spacing scale.
  static const double xs = 2;
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 24;

  // Corner radii.
  static const double radiusSm = 4;
  static const double radiusMd = 6;
  static const double radiusLg = 8;

  // Icon sizes.
  static const double iconSm = 12;
  static const double iconMd = 14;
  static const double iconLg = 16;

  // Common paddings.
  static const EdgeInsets buttonPadding =
      EdgeInsets.symmetric(horizontal: 14, vertical: 7);
  static const EdgeInsets toolbarButtonPadding =
      EdgeInsets.symmetric(horizontal: 10, vertical: 6);
  static const EdgeInsets menuItemPadding =
      EdgeInsets.symmetric(horizontal: 12, vertical: 6);
  static const EdgeInsets dialogPadding = EdgeInsets.fromLTRB(20, 16, 20, 16);

  // Motion.
  static const Duration hoverDuration = Duration(milliseconds: 80);
  static const Duration switchDuration = Duration(milliseconds: 180);

  // Fixed chrome sizes.
  static const double statusBarHeight = 24;
  static const double titleBarHeight = 38;
}
