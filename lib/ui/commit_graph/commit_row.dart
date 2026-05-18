import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../application/commit_graph/commit_node.dart';
import '../common/author_avatar.dart';
import '../theme/app_palette.dart';
import 'lane_painter.dart';
import 'ref_decoration.dart';
import 'ref_pill.dart';

class CommitRow extends StatelessWidget {
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

  const CommitRow({
    super.key,
    required this.node,
    required this.maxLane,
    required this.refs,
    required this.isSelected,
    required this.onTap,
    this.onSecondaryTap,
    this.onRefTap,
    this.onRefDoubleTap,
  });

  static final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bg = isSelected ? palette.bgAccent : Colors.transparent;
    final textColor = isSelected ? Colors.white : palette.fg0;
    final mutedColor = isSelected ? Colors.white70 : palette.fg1;
    final dateColor = isSelected ? Colors.white70 : palette.fg2;
    final shaColor = isSelected ? Colors.white : palette.accentRemote;

    return Material(
      color: bg,
      child: GestureDetector(
        onSecondaryTapDown: onSecondaryTap != null
            ? (details) => onSecondaryTap!(details.globalPosition)
            : null,
        child: InkWell(
          onTap: onTap,
          hoverColor: palette.bg4,
          child: SizedBox(
            height: kRowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
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
                                onTap:
                                    onRefTap == null ? null : () => onRefTap!(r),
                                onDoubleTap: onRefDoubleTap == null ||
                                        r.isCurrent
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
                            style:
                                TextStyle(color: mutedColor, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 130,
                    child: Text(
                      _dateFmt.format(node.commit.author.when.toLocal()),
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
            ),
          ),
        ),
      ),
    );
  }
}
