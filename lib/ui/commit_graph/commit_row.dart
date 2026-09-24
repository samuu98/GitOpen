import 'package:flutter/material.dart';
import 'package:gitopen/application/commit_graph/commit_node.dart';
import 'package:gitopen/application/commits/co_authors.dart';
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
    this.bisectMarkers = const [],
  });
  final CommitNode node;
  final int maxLane;
  final List<RefDecoration> refs;
  final List<BisectMarker> bisectMarkers;
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
    final textColor = palette.fg0;
    final mutedColor = palette.fg1;
    final dateColor = palette.fg2;
    final shaColor = isSelected ? palette.fg0 : palette.accentRemote;
    final date = _dateFmt.format(node.commit.author.when.toLocal());
    final refLabel = refs.isEmpty
        ? ''
        : ', refs ${refs.map((r) => r.name).join(', ')}';
    final authorEmail = node.commit.author.email.toLowerCase();
    final coAuthors = parseCoAuthors(
      node.commit.message,
    ).where((c) => c.email.toLowerCase() != authorEmail).toList();

    return AppAnimatedRow(
      selected: isSelected,
      semanticLabel:
          'Commit ${node.commit.sha.short()}, ${node.commit.summary}, '
          'by ${node.commit.author.name}, $date$refLabel',
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTap == null
          ? null
          : (details) => onSecondaryTap!(details.globalPosition),
      height: AppSpacing.of(context).graphRowHeight,
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.of(context).md),
      child: Row(
        children: [
          SizedBox(
            width: svgWidth(maxLane),
            height: AppSpacing.of(context).graphRowHeight,
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
                  for (final marker in bisectMarkers)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _BisectPill(marker: marker),
                    ),
                  if (bisectMarkers.isNotEmpty) const SizedBox(width: 4),
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
                if (coAuthors.isEmpty)
                  AuthorAvatar(
                    name: node.commit.author.name,
                    email: node.commit.author.email,
                    size: AppSpacing.of(context).regularIconSize,
                  )
                else
                  _AvatarCluster(
                    people: [
                      (
                        name: node.commit.author.name,
                        email: node.commit.author.email,
                      ),
                      ...coAuthors,
                    ],
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

enum BisectMarker { candidate, good, bad, firstBad }

class _BisectPill extends StatelessWidget {
  const _BisectPill({required this.marker});

  final BisectMarker marker;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (label, color) = switch (marker) {
      BisectMarker.candidate => ('Candidate', palette.accentRemote),
      BisectMarker.good => ('Good', palette.accentCurrent),
      BisectMarker.bad => ('Bad', palette.accentWarn),
      BisectMarker.firstBad => ('First bad', palette.accentErr),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: palette.bg2,
        border: Border.all(color: color),
        borderRadius: AppRadii.of(context).controlRadius,
      ),
      child: Text(
        label,
        style: AppTypography.of(context).captionStrong.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Overlapping avatar stack for a co-authored commit: the author first, then
/// each co-author, capped at [_maxAvatars] with a `+N` disc for the rest.
class _AvatarCluster extends StatelessWidget {
  const _AvatarCluster({required this.people});

  /// Author first, then co-authors.
  final List<CoAuthor> people;

  static const double _size = 16;
  static const double _ring = 1.5;
  static const double _step = 10;
  static const int _maxAvatars = 3;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final shown = people.length > _maxAvatars
        ? people.take(_maxAvatars).toList()
        : people;
    final overflow = people.length - shown.length;
    final slots = shown.length + (overflow > 0 ? 1 : 0);
    final width = _size + _ring * 2 + (slots - 1) * _step;

    final layers = <Widget>[
      for (var i = 0; i < shown.length; i++)
        Positioned(
          left: i * _step,
          child: _ringed(
            palette,
            AuthorAvatar(
              name: shown[i].name,
              email: shown[i].email,
              size: _size,
            ),
          ),
        ),
      if (overflow > 0)
        Positioned(
          left: shown.length * _step,
          child: _ringed(palette, _overflowDisc(palette, overflow)),
        ),
    ];

    return Tooltip(
      message: 'Co-authored — ${people.map((p) => p.name).join(', ')}',
      child: SizedBox(
        width: width,
        height: _size + _ring * 2,
        child: Stack(clipBehavior: Clip.none, children: layers),
      ),
    );
  }

  Widget _ringed(AppPalette palette, Widget child) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: palette.bg1, width: _ring),
      ),
      child: child,
    );
  }

  Widget _overflowDisc(AppPalette palette, int n) {
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: palette.bg4, shape: BoxShape.circle),
      child: Text(
        '+$n',
        style: TextStyle(
          color: palette.fg1,
          fontSize: _size * 0.38,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
