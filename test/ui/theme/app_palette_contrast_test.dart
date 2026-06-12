import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

double _linear(int channel) {
  final c = channel / 255.0;
  return c <= 0.03928
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

int _channel(double value) => (value * 255).round().clamp(0, 255);

double _luminance(Color c) =>
    0.2126 * _linear(_channel(c.r)) +
    0.7152 * _linear(_channel(c.g)) +
    0.0722 * _linear(_channel(c.b));

double _contrast(Color a, Color b) {
  final l1 = _luminance(a);
  final l2 = _luminance(b);
  final high = l1 > l2 ? l1 : l2;
  final low = l1 > l2 ? l2 : l1;
  return (high + 0.05) / (low + 0.05);
}

void _expectAa(String label, Color fg, Color bg) {
  expect(
    _contrast(fg, bg),
    greaterThanOrEqualTo(4.5),
    reason: '$label should meet WCAG AA normal-text contrast',
  );
}

void main() {
  test('dark palette text colors meet AA on common backgrounds', () {
    final p = AppPalette.dark();
    _expectAa('dark fg0/bg1', p.fg0, p.bg1);
    _expectAa('dark fg1/bg1', p.fg1, p.bg1);
    _expectAa('dark fg2/bg1', p.fg2, p.bg1);
    _expectAa('dark fg3/bg1', p.fg3, p.bg1);
    _expectAa('dark remote/bg1', p.accentRemote, p.bg1);
    _expectAa('dark current/bg1', p.accentCurrent, p.bg1);
    _expectAa('dark err/bg1', p.accentErr, p.bg1);
  });

  test('light palette text colors meet AA on common backgrounds', () {
    final p = AppPalette.light();
    _expectAa('light fg0/bg1', p.fg0, p.bg1);
    _expectAa('light fg1/bg1', p.fg1, p.bg1);
    _expectAa('light fg2/bg1', p.fg2, p.bg1);
    _expectAa('light fg3/bg1', p.fg3, p.bg1);
    _expectAa('light remote/bg1', p.accentRemote, p.bg1);
    _expectAa('light current/bg1', p.accentCurrent, p.bg1);
    _expectAa('light err/bg1', p.accentErr, p.bg1);
  });
}
