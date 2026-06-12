import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';

void main() {
  test('desktop tokens expose the 4 px spacing scale', () {
    const spacing = AppSpacing.desktop();
    expect(spacing.xxs, 4);
    expect(spacing.xs, 6);
    expect(spacing.sm, 8);
    expect(spacing.md, 12);
    expect(spacing.lg, 16);
    expect(spacing.xl, 24);
    expect(spacing.xxl, 32);
    expect(spacing.panel, const EdgeInsets.all(12));
    expect(
      spacing.row,
      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
    expect(
      spacing.compactRow,
      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  });

  test('desktop radii expose compact control geometry', () {
    const radii = AppRadii.desktop();
    expect(radii.control, 4);
    expect(radii.row, 4);
    expect(radii.panel, 6);
    expect(radii.dialog, 8);
    expect(radii.pill, 999);
    expect(radii.rowRadius, BorderRadius.circular(4));
  });

  test('desktop typography exposes compact text styles', () {
    const typography = AppTypography.desktop();
    expect(typography.caption.fontSize, 11.5);
    expect(typography.captionStrong.fontWeight, FontWeight.w600);
    expect(typography.body.fontSize, 12.5);
    expect(typography.bodyStrong.fontWeight, FontWeight.w600);
    expect(typography.title.fontSize, 14);
    expect(typography.title.fontWeight, FontWeight.w700);
    expect(typography.mono.fontSize, 12);
    expect(typography.mono.fontFamily, 'monospace');
    expect(typography.monoSmall.fontSize, 11);
    expect(typography.monoSmall.fontFamily, 'monospace');
  });

  test('motion tokens stay within the S4 120-200 ms range', () {
    const motion = AppMotion.standard();
    expect(motion.fast, const Duration(milliseconds: 120));
    expect(motion.normal, const Duration(milliseconds: 160));
    expect(motion.slow, const Duration(milliseconds: 200));
    expect(motion.curve.transform(1), 1);
  });

  test('extensions are available from ThemeData', () {
    final theme = ThemeData(
      extensions: const [
        AppSpacing.desktop(),
        AppRadii.desktop(),
        AppTypography.desktop(),
        AppMotion.standard(),
      ],
    );
    expect(theme.extension<AppSpacing>()!.md, 12);
    expect(theme.extension<AppRadii>()!.row, 4);
    expect(theme.extension<AppTypography>()!.body.fontSize, 12.5);
    expect(theme.extension<AppMotion>()!.normal.inMilliseconds, 160);
  });

  test('numeric extensions lerp predictably', () {
    const a = AppSpacing(
      xxs: 4,
      xs: 6,
      sm: 8,
      md: 12,
      lg: 16,
      xl: 24,
      xxl: 32,
    );
    const b = AppSpacing(
      xxs: 8,
      xs: 10,
      sm: 12,
      md: 16,
      lg: 20,
      xl: 28,
      xxl: 36,
    );
    expect(a.lerp(b, 0.5).md, 14);
  });
}
