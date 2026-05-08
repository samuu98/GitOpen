import '../../domain/commits/commit_info.dart';
import '../../domain/commits/commit_sha.dart';
import 'commit_node.dart';
import 'lane_segment.dart';

abstract interface class CommitGraphLayout {
  List<CommitNode> compute(List<CommitInfo> commitsNewestFirst);
}

final class DefaultCommitGraphLayout implements CommitGraphLayout {
  const DefaultCommitGraphLayout();

  @override
  List<CommitNode> compute(List<CommitInfo> commitsNewestFirst) {
    if (commitsNewestFirst.isEmpty) return const [];

    // Active lanes: index -> sha that this lane is currently waiting to render.
    final lanes = <CommitSha?>[];
    final laneColor = <int, int>{};
    var nextColor = 0;
    final result = <CommitNode>[];

    // Snapshot of `lanes` at the start of the previous row (used to draw
    // top segments — i.e., segments that connect the previous row's lane
    // positions to this row's lane positions).
    var prevLanes = <CommitSha?>[];

    for (final commit in commitsNewestFirst) {
      // 1) Find or allocate this commit's lane.
      var ownLane = -1;
      for (var i = 0; i < lanes.length; i++) {
        if (lanes[i] == commit.sha) {
          ownLane = i;
          break;
        }
      }
      if (ownLane == -1) {
        ownLane = lanes.indexOf(null);
        if (ownLane == -1) {
          ownLane = lanes.length;
          lanes.add(null);
        }
      }
      if (!laneColor.containsKey(ownLane)) laneColor[ownLane] = nextColor++;
      final ownColor = laneColor[ownLane]!;

      // 2) Top segments: each previously-active lane connects from its
      //    previous index (at y=0) to its position at y=12. Lanes that
      //    were waiting for THIS commit converge to ownLane; everyone
      //    else continues straight down.
      final topSegments = <LaneSegment>[];
      for (var i = 0; i < prevLanes.length; i++) {
        if (prevLanes[i] == null) continue;
        final int toLane;
        final int color;
        if (prevLanes[i] == commit.sha) {
          toLane = ownLane;
          color = ownColor;
        } else {
          toLane = i;
          color = laneColor[i] ?? 0;
        }
        topSegments.add(LaneSegment(i, toLane, color));
      }

      // 3) Free our own lane; first parent (if any) will reclaim it.
      lanes[ownLane] = null;

      // 4) Assign parents to lanes.
      final parentLaneIndices = <int>[];
      for (var pi = 0; pi < commit.parentShas.length; pi++) {
        final parentSha = commit.parentShas[pi];

        // If a lane already waits for this parent, reuse it.
        var existing = -1;
        for (var i = 0; i < lanes.length; i++) {
          if (lanes[i] == parentSha) {
            existing = i;
            break;
          }
        }
        if (existing >= 0) {
          parentLaneIndices.add(existing);
          continue;
        }

        final int targetLane;
        if (pi == 0) {
          targetLane = ownLane;
          lanes[ownLane] = parentSha;
        } else {
          targetLane = lanes.indexOf(null);
          if (targetLane == -1) {
            final newIdx = lanes.length;
            lanes.add(parentSha);
            if (!laneColor.containsKey(newIdx)) laneColor[newIdx] = nextColor++;
            parentLaneIndices.add(newIdx);
            continue;
          } else {
            lanes[targetLane] = parentSha;
            if (!laneColor.containsKey(targetLane)) laneColor[targetLane] = nextColor++;
          }
        }
        parentLaneIndices.add(targetLane);
      }

      // Trim trailing nulls so the lane width stays minimal.
      while (lanes.isNotEmpty && lanes.last == null) {
        lanes.removeLast();
      }

      // 5) Bottom segments: each currently-active lane connects from
      //    y=12 to y=24. A lane that holds one of this commit's parents
      //    starts at the commit dot (ownLane); other lanes pass through
      //    on the same index.
      final bottomSegments = <LaneSegment>[];
      for (var i = 0; i < lanes.length; i++) {
        if (lanes[i] == null) continue;
        final int fromLane;
        if (parentLaneIndices.contains(i)) {
          fromLane = ownLane;
        } else {
          fromLane = i;
        }
        final color = laneColor[i] ?? 0;
        bottomSegments.add(LaneSegment(fromLane, i, color));
      }

      result.add(CommitNode(
        commit: commit,
        lane: ownLane,
        color: ownColor,
        topSegments: topSegments,
        bottomSegments: bottomSegments,
      ));

      // 6) Snapshot lanes for the next row's top-segment computation.
      prevLanes = List<CommitSha?>.of(lanes);
    }

    return result;
  }
}
