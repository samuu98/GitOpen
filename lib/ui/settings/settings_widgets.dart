import 'package:flutter/material.dart';
import '../theme/app_palette.dart';

/// Title strip at the top of every settings section: bold page name plus an
/// optional short description.
class SettingsPageHeader extends StatelessWidget {
  final String title;
  final String? description;
  const SettingsPageHeader({super.key, required this.title, this.description});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: palette.fg0,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(
              description!,
              style: TextStyle(color: palette.fg2, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// Subsection title — small uppercase label with a hairline underline
/// for the card that follows it.
class SettingsSectionTitle extends StatelessWidget {
  final String text;
  const SettingsSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: palette.fg2,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

/// Rounded panel used for groups of settings rows. Matches the dialog frame
/// look — bg2 with a 1px border and 8px radius.
class SettingsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const SettingsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.bg2,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: padding,
      child: child,
    );
  }
}

/// Label/control row inside a [SettingsCard]. Optionally adds a hairline
/// divider below.
class SettingsRow extends StatelessWidget {
  final String label;
  final String? description;
  final Widget child;
  final bool divider;
  final double labelWidth;
  const SettingsRow({
    super.key,
    required this.label,
    required this.child,
    this.description,
    this.divider = true,
    this.labelWidth = 180,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: divider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.border)))
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: labelWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(color: palette.fg0, fontSize: 12.5),
                ),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      description!,
                      style:
                          TextStyle(color: palette.fg3, fontSize: 11),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Vertical gap used between [SettingsCard]s.
class SettingsGap extends StatelessWidget {
  const SettingsGap({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(height: 22);
}
