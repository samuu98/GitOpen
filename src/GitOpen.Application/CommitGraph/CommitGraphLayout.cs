using GitOpen.Domain.Commits;

namespace GitOpen.Application.CommitGraph;

public sealed class CommitGraphLayout : ICommitGraphLayout
{
    public IReadOnlyList<CommitNode> Compute(IReadOnlyList<CommitInfo> commitsNewestFirst)
    {
        if (commitsNewestFirst.Count == 0) return Array.Empty<CommitNode>();

        // Active lanes: index -> sha that this lane is currently waiting to render.
        var lanes = new List<CommitSha?>();
        var laneColor = new Dictionary<int, int>();
        var nextColor = 0;
        var result = new List<CommitNode>(commitsNewestFirst.Count);

        // Snapshot of `lanes` at the start of the previous row (used to draw
        // top segments — i.e., segments that connect the previous row's lane
        // positions to this row's lane positions).
        var prevLanes = new List<CommitSha?>();

        foreach (var commit in commitsNewestFirst)
        {
            // 1) Find or allocate this commit's lane.
            var ownLane = -1;
            for (var i = 0; i < lanes.Count; i++)
            {
                if (lanes[i] == commit.Sha) { ownLane = i; break; }
            }
            if (ownLane == -1)
            {
                ownLane = lanes.IndexOf(null);
                if (ownLane == -1) { ownLane = lanes.Count; lanes.Add(null); }
            }
            if (!laneColor.ContainsKey(ownLane)) laneColor[ownLane] = nextColor++;
            var ownColor = laneColor[ownLane];

            // 2) Top segments: each previously-active lane connects from its
            //    previous index (at y=0) to its position at y=12. Lanes that
            //    were waiting for THIS commit converge to ownLane; everyone
            //    else continues straight down.
            var topSegments = new List<LaneSegment>();
            for (var i = 0; i < prevLanes.Count; i++)
            {
                if (prevLanes[i] is null) continue;
                int toLane;
                int color;
                if (prevLanes[i] == commit.Sha)
                {
                    toLane = ownLane;
                    color = ownColor;
                }
                else
                {
                    toLane = i;
                    color = laneColor.TryGetValue(i, out var c) ? c : 0;
                }
                topSegments.Add(new LaneSegment(i, toLane, color));
            }

            // 3) Free our own lane; first parent (if any) will reclaim it.
            lanes[ownLane] = null;

            // 4) Assign parents to lanes.
            var parentLaneIndices = new List<int>(commit.ParentShas.Count);
            for (var pi = 0; pi < commit.ParentShas.Count; pi++)
            {
                var parentSha = commit.ParentShas[pi];

                // If a lane already waits for this parent, reuse it.
                var existing = -1;
                for (var i = 0; i < lanes.Count; i++)
                    if (lanes[i] == parentSha) { existing = i; break; }
                if (existing >= 0) { parentLaneIndices.Add(existing); continue; }

                int targetLane;
                if (pi == 0)
                {
                    targetLane = ownLane;
                    lanes[ownLane] = parentSha;
                }
                else
                {
                    targetLane = lanes.IndexOf(null);
                    if (targetLane == -1) { targetLane = lanes.Count; lanes.Add(parentSha); }
                    else lanes[targetLane] = parentSha;
                    if (!laneColor.ContainsKey(targetLane)) laneColor[targetLane] = nextColor++;
                }
                parentLaneIndices.Add(targetLane);
            }

            // Trim trailing nulls so the lane width stays minimal.
            while (lanes.Count > 0 && lanes[^1] is null) lanes.RemoveAt(lanes.Count - 1);

            // 5) Bottom segments: each currently-active lane connects from
            //    y=12 to y=24. A lane that holds one of this commit's parents
            //    starts at the commit dot (ownLane); other lanes pass through
            //    on the same index.
            var bottomSegments = new List<LaneSegment>();
            for (var i = 0; i < lanes.Count; i++)
            {
                if (lanes[i] is null) continue;
                int fromLane;
                if (parentLaneIndices.Contains(i))
                {
                    fromLane = ownLane;
                }
                else
                {
                    fromLane = i;
                }
                var color = laneColor.TryGetValue(i, out var c) ? c : 0;
                bottomSegments.Add(new LaneSegment(fromLane, i, color));
            }

            result.Add(new CommitNode(commit, ownLane, ownColor, topSegments, bottomSegments));

            // 6) Snapshot lanes for the next row's top-segment computation.
            prevLanes = new List<CommitSha?>(lanes);
        }

        return result;
    }
}
