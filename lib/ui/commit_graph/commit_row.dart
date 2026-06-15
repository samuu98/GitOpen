import 'package:flutter/material.dart';
import 'package:gitopen/application/commit_graph/commit_node.dart';
import 'package:gitopen/ui/commit_graph/lane_painter.dart';
import 'package:gitopen/ui/commit_graph/ref_decoration.dart';
import 'package:gitopen/ui/commit_graph/ref_pill.dart';
import 'package:gitopen/ui/common/app_animated_row.dart';
import 'package:gitopen/ui/common/author_avatar.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:intl/intl.dart';

class CommitRow extends StatelessWidget {
  const CommitRow({
    required this.node,
    required this.maxLane,
    required this.refs,
    required this.isSelected,
    required this.onTap,
    super.key,
    this.onSecondaryTap,
    this.onRefTap,
    this.onRefDoubleTap,
  });
  final CommitNode node;
  final int maxLane;
  final List<RefDecoration> refs;
  final bool isSelected;
  final VoidCallback onTap;

  /// Called when the user right-clicks / secondary-taps on this row.
  /// Receives the global position of the tap for context-menu placement.
  final void Function(Offset globalPosition)? onSecondaryTap;

  /// Called when the user left-clicks one of the ref pills.
  final void Function(RefDecoration ref)? onRefTap;

  /// Called when the user double-clicks one of the ref pills.
  final void Function(RefDecoration ref)? onRefDoubleTap;

  static final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final textColor = isSelected ? Colors.white : palette.fg0;
    final mutedColor = isSelected ? Colors.white70 : palette.fg1;
    final dateColor = isSelected ? Colors.white70 : palette.fg2;
    final shaColor = isSelected ? Colors.white : palette.accentRemote;
    final date = _dateFmt.format(node.commit.author.when.toLocal());
    final refLabel = refs.isEmpty
        ? ''
        : ', refs ${refs.map((r) => r.name).join(', ')}';

    return AppAnimatedRow(
      selected: isSelected,
      semanticLabel:
          'Commit ${node.commit.sha.short()}, ${node.commit.summary}, '
          'by ${node.commit.author.name}, $date$refLabel',
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTap == null
          ? null
          : (details) => onSecondaryTap!(details.globalPosition),
      height: kRowHeight,
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.of(context).md),
      child: Row(
        children: [
          SizedBox(
            width: svgWidth(maxLane),
            height: kRowHeight,
            child: CustomPaint(
              painter: LanePainter(
                node: node,
                maxLane: maxLane,
                lanePalette: palette.lanePalette,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 70,
            child: Text(
              node.commit.sha.short(),
              style: TextStyle(
                color: shaColor,
                fontFamily: 'monospace',
                fontSize: 11.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRect(
              child: Row(
                children: [
                  for (final r in refs)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: RefPill(
                        decoration: r,
                        onTap: onRefTap == null ? null : () => onRefTap!(r),
                        onDoubleTap: onRefDoubleTap == null || r.isCurrent
                            ? null
                            : () => onRefDoubleTap!(r),
                      ),
                    ),
                  if (refs.isNotEmpty) const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      node.commit.summary,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(color: textColor, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 180,
            child: Row(
              children: [
                AuthorAvatar(
                  name: node.commit.author.name,
                  email: node.commit.author.email,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.commit.author.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: mutedColor, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: Text(
              date,
              style: TextStyle(
                color: dateColor,
                fontSize: 11.5,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
