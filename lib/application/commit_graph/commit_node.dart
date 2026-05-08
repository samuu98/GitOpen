import 'package:equatable/equatable.dart';

import '../../domain/commits/commit_info.dart';
import 'lane_segment.dart';

final class CommitNode extends Equatable {
  final CommitInfo commit;
  final int lane;
  final int color;
  final List<LaneSegment> topSegments;
  final List<LaneSegment> bottomSegments;

  const CommitNode({
    required this.commit,
    required this.lane,
    required this.color,
    required this.topSegments,
    required this.bottomSegments,
  });

  @override
  List<Object?> get props => [commit, lane, color, topSegments, bottomSegments];
}
