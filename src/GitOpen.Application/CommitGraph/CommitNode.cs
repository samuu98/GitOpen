using GitOpen.Domain.Commits;

namespace GitOpen.Application.CommitGraph;

public sealed record LaneSegment(int FromLane, int ToLane, int Color);

public sealed record CommitNode(
    CommitInfo Commit,
    int Lane,
    int Color,
    IReadOnlyList<LaneSegment> TopSegments,
    IReadOnlyList<LaneSegment> BottomSegments);
