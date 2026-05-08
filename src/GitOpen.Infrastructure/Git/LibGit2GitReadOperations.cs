using System.Runtime.CompilerServices;
using GitOpen.Application.Git;
using GitOpen.Domain.Commits;
using GitOpen.Domain.Diff;
using GitOpen.Domain.Files;
using GitOpen.Domain.Refs;
using GitOpen.Domain.Repositories;
using GitOpen.Domain.Status;

namespace GitOpen.Infrastructure.Git;

public sealed class LibGit2GitReadOperations : IGitReadOperations
{
    public Task<RepoStatus> GetStatusAsync(RepoLocation repo, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        using var lg = new LibGit2Sharp.Repository(repo.Path);
        var head = lg.Head;
        CommitSha? headSha = head.Tip is null ? null : new CommitSha(head.Tip.Sha);
        var entries = new List<WorkingFileEntry>();

        foreach (var s in lg.RetrieveStatus(new LibGit2Sharp.StatusOptions()))
        {
            var (idxState, wtState) = MapStatus(s.State);
            if (idxState == WorkingFileState.Unmodified && wtState == WorkingFileState.Unmodified) continue;
            entries.Add(new WorkingFileEntry(s.FilePath, idxState, wtState));
        }

        return Task.FromResult(new RepoStatus(
            head.IsRemote ? null : head.FriendlyName,
            headSha,
            IsDetached: lg.Info.IsHeadDetached,
            IsBare: lg.Info.IsBare,
            entries));
    }

    private static (WorkingFileState index, WorkingFileState worktree) MapStatus(LibGit2Sharp.FileStatus s)
    {
        var idx = WorkingFileState.Unmodified;
        var wt = WorkingFileState.Unmodified;

        if (s.HasFlag(LibGit2Sharp.FileStatus.NewInIndex))      idx = WorkingFileState.Added;
        if (s.HasFlag(LibGit2Sharp.FileStatus.ModifiedInIndex)) idx = WorkingFileState.Modified;
        if (s.HasFlag(LibGit2Sharp.FileStatus.DeletedFromIndex))idx = WorkingFileState.Deleted;
        if (s.HasFlag(LibGit2Sharp.FileStatus.RenamedInIndex))  idx = WorkingFileState.Renamed;

        if (s.HasFlag(LibGit2Sharp.FileStatus.NewInWorkdir))       wt = WorkingFileState.Untracked;
        if (s.HasFlag(LibGit2Sharp.FileStatus.ModifiedInWorkdir))  wt = WorkingFileState.Modified;
        if (s.HasFlag(LibGit2Sharp.FileStatus.DeletedFromWorkdir)) wt = WorkingFileState.Deleted;
        if (s.HasFlag(LibGit2Sharp.FileStatus.RenamedInWorkdir))   wt = WorkingFileState.Renamed;
        if (s.HasFlag(LibGit2Sharp.FileStatus.Conflicted))         wt = WorkingFileState.Conflicted;
        if (s.HasFlag(LibGit2Sharp.FileStatus.Ignored))            wt = WorkingFileState.Ignored;

        return (idx, wt);
    }

    public async IAsyncEnumerable<CommitInfo> GetCommitsAsync(
        RepoLocation repo,
        CommitQuery query,
        [EnumeratorCancellation] CancellationToken ct)
    {
        // Photino.Blazor's SynchronousTaskScheduler runs continuations inline,
        // so any per-iteration await (e.g. Task.Yield) recurses on the call
        // stack and overflows after a few thousand commits. We iterate
        // synchronously here; callers that want concurrency wrap in Task.Run.
        await Task.CompletedTask;

        using var lg = new LibGit2Sharp.Repository(repo.Path);
        var filter = new LibGit2Sharp.CommitFilter
        {
            SortBy = LibGit2Sharp.CommitSortStrategies.Topological | LibGit2Sharp.CommitSortStrategies.Time
        };
        if (query.RefSpec is not null) filter.IncludeReachableFrom = query.RefSpec;

        IEnumerable<LibGit2Sharp.Commit> commits = lg.Commits.QueryBy(filter);
        if (query.Skip is { } s) commits = commits.Skip(s);
        if (query.Take is { } t) commits = commits.Take(t);

        foreach (var c in commits)
        {
            ct.ThrowIfCancellationRequested();
            yield return new CommitInfo(
                new CommitSha(c.Sha),
                c.Parents.Select(p => new CommitSha(p.Sha)).ToList(),
                new CommitSignature(c.Author.Name, c.Author.Email, c.Author.When),
                new CommitSignature(c.Committer.Name, c.Committer.Email, c.Committer.When),
                c.MessageShort,
                c.Message);
        }
    }

    public Task<IReadOnlyList<Branch>> GetBranchesAsync(RepoLocation repo, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        using var lg = new LibGit2Sharp.Repository(repo.Path);
        var headName = lg.Head.CanonicalName;
        var branches = lg.Branches.Select(b => new Branch(
            Name: b.FriendlyName,
            FullName: b.CanonicalName,
            IsRemote: b.IsRemote,
            IsCurrent: b.CanonicalName == headName,
            TipSha: b.Tip is null ? null : new CommitSha(b.Tip.Sha),
            UpstreamFullName: b.TrackedBranch?.CanonicalName,
            Ahead: b.TrackingDetails?.AheadBy ?? 0,
            Behind: b.TrackingDetails?.BehindBy ?? 0)).ToList();
        return Task.FromResult<IReadOnlyList<Branch>>(branches);
    }

    public Task<IReadOnlyList<Tag>> GetTagsAsync(RepoLocation repo, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        using var lg = new LibGit2Sharp.Repository(repo.Path);
        var tags = lg.Tags.Select(t => new Tag(
            Name: t.FriendlyName,
            FullName: t.CanonicalName,
            TargetSha: new CommitSha(t.Target.Sha),
            IsAnnotated: t.IsAnnotated)).ToList();
        return Task.FromResult<IReadOnlyList<Tag>>(tags);
    }

    public Task<IReadOnlyList<Remote>> GetRemotesAsync(RepoLocation repo, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        using var lg = new LibGit2Sharp.Repository(repo.Path);
        var remotes = lg.Network.Remotes.Select(r =>
        {
            var remoteBranches = lg.Branches
                .Where(b => b.IsRemote && b.RemoteName == r.Name)
                .Select(b => new Branch(
                    b.FriendlyName, b.CanonicalName, IsRemote: true, IsCurrent: false,
                    TipSha: b.Tip is null ? null : new CommitSha(b.Tip.Sha),
                    UpstreamFullName: null, Ahead: 0, Behind: 0))
                .ToList();
            return new Remote(r.Name, r.Url, remoteBranches);
        }).ToList();
        return Task.FromResult<IReadOnlyList<Remote>>(remotes);
    }

    public Task<IReadOnlyList<Stash>> GetStashesAsync(RepoLocation repo, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        using var lg = new LibGit2Sharp.Repository(repo.Path);
        var stashes = lg.Stashes.Select((s, i) => new Stash(
            Index: i,
            Sha: new CommitSha(s.WorkTree.Sha),
            Message: s.Message ?? "",
            CreatedAt: s.WorkTree.Committer.When)).ToList();
        return Task.FromResult<IReadOnlyList<Stash>>(stashes);
    }

    public Task<DiffResult> GetDiffAsync(RepoLocation repo, DiffSpec spec, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        using var lg = new LibGit2Sharp.Repository(repo.Path);

        LibGit2Sharp.Tree? oldTree;
        LibGit2Sharp.Tree? newTree;

        switch (spec)
        {
            case DiffSpec.CommitVsParent cvp:
                var c = lg.Lookup(cvp.CommitSha.Value, LibGit2Sharp.ObjectType.Commit) as LibGit2Sharp.Commit
                    ?? throw new InvalidOperationException($"Commit {cvp.CommitSha} not found");
                newTree = c.Tree;
                oldTree = c.Parents.FirstOrDefault()?.Tree;
                break;
            case DiffSpec.CommitVsCommit cvc:
                var from = lg.Lookup(cvc.From.Value, LibGit2Sharp.ObjectType.Commit) as LibGit2Sharp.Commit;
                var to = lg.Lookup(cvc.To.Value, LibGit2Sharp.ObjectType.Commit) as LibGit2Sharp.Commit;
                oldTree = from?.Tree;
                newTree = to?.Tree;
                break;
            case DiffSpec.IndexVsHead:
                oldTree = lg.Head.Tip?.Tree;
                newTree = null;
                break;
            case DiffSpec.WorkingTreeVsIndex:
                oldTree = null;
                newTree = null;
                break;
            default:
                throw new NotSupportedException();
        }

        LibGit2Sharp.TreeChanges changes = spec switch
        {
            DiffSpec.WorkingTreeVsIndex =>
                lg.Diff.Compare<LibGit2Sharp.TreeChanges>(
                    lg.Head.Tip?.Tree,
                    LibGit2Sharp.DiffTargets.WorkingDirectory | LibGit2Sharp.DiffTargets.Index),
            DiffSpec.IndexVsHead =>
                lg.Diff.Compare<LibGit2Sharp.TreeChanges>(
                    lg.Head.Tip?.Tree, LibGit2Sharp.DiffTargets.Index),
            _ => lg.Diff.Compare<LibGit2Sharp.TreeChanges>(oldTree, newTree)
        };

        var patch = spec switch
        {
            DiffSpec.WorkingTreeVsIndex =>
                lg.Diff.Compare<LibGit2Sharp.Patch>(
                    lg.Head.Tip?.Tree,
                    LibGit2Sharp.DiffTargets.WorkingDirectory | LibGit2Sharp.DiffTargets.Index),
            DiffSpec.IndexVsHead =>
                lg.Diff.Compare<LibGit2Sharp.Patch>(
                    lg.Head.Tip?.Tree, LibGit2Sharp.DiffTargets.Index),
            _ => lg.Diff.Compare<LibGit2Sharp.Patch>(oldTree, newTree)
        };

        var files = new List<FileDiff>();
        foreach (var change in changes)
        {
            ct.ThrowIfCancellationRequested();
            var p = patch[change.Path];
            var hunks = ParsePatch(p?.Patch ?? "");
            files.Add(new FileDiff(
                Path: change.Path,
                OldPath: change.OldPath != change.Path ? change.OldPath : null,
                ChangeKind: MapChangeKind(change.Status),
                IsBinary: p?.IsBinaryComparison ?? false,
                LinesAdded: p?.LinesAdded ?? 0,
                LinesDeleted: p?.LinesDeleted ?? 0,
                Hunks: hunks));
        }

        return Task.FromResult(new DiffResult(files));
    }

    private static FileChangeKind MapChangeKind(LibGit2Sharp.ChangeKind k) => k switch
    {
        LibGit2Sharp.ChangeKind.Added       => FileChangeKind.Added,
        LibGit2Sharp.ChangeKind.Deleted     => FileChangeKind.Deleted,
        LibGit2Sharp.ChangeKind.Modified    => FileChangeKind.Modified,
        LibGit2Sharp.ChangeKind.Renamed     => FileChangeKind.Renamed,
        LibGit2Sharp.ChangeKind.Copied      => FileChangeKind.Copied,
        LibGit2Sharp.ChangeKind.TypeChanged => FileChangeKind.TypeChanged,
        LibGit2Sharp.ChangeKind.Conflicted  => FileChangeKind.Unmerged,
        _ => FileChangeKind.Modified
    };

    private static IReadOnlyList<DiffHunk> ParsePatch(string patch)
    {
        if (string.IsNullOrEmpty(patch)) return Array.Empty<DiffHunk>();
        var hunks = new List<DiffHunk>();
        var lines = patch.Split('\n');
        DiffHunk? current = null;
        var hunkLines = new List<DiffLine>();
        var oldLine = 0;
        var newLine = 0;
        var oldStart = 0;
        var oldCount = 0;
        var newStart = 0;
        var newCount = 0;

        void Flush()
        {
            if (current is null) return;
            hunks.Add(current with { Lines = hunkLines.ToList() });
            hunkLines.Clear();
            current = null;
        }

        foreach (var raw in lines)
        {
            var line = raw.TrimEnd('\r');
            if (line.StartsWith("@@", StringComparison.Ordinal))
            {
                Flush();
                ParseHunkHeader(line, out oldStart, out oldCount, out newStart, out newCount);
                oldLine = oldStart;
                newLine = newStart;
                current = new DiffHunk(oldStart, oldCount, newStart, newCount, line, Array.Empty<DiffLine>());
                continue;
            }
            if (current is null) continue;
            if (line.Length == 0) continue;
            switch (line[0])
            {
                case '+': hunkLines.Add(new DiffLine(DiffLineKind.Addition, null, newLine++, line.Substring(1))); break;
                case '-': hunkLines.Add(new DiffLine(DiffLineKind.Deletion, oldLine++, null, line.Substring(1))); break;
                case ' ': hunkLines.Add(new DiffLine(DiffLineKind.Context, oldLine++, newLine++, line.Substring(1))); break;
                default: break;
            }
        }
        Flush();
        return hunks;
    }

    private static void ParseHunkHeader(string s, out int oldStart, out int oldCount, out int newStart, out int newCount)
    {
        // Format: @@ -oldStart,oldCount +newStart,newCount @@
        oldStart = oldCount = newStart = newCount = 0;
        var minus = s.IndexOf('-');
        var plus = s.IndexOf('+');
        if (minus < 0 || plus < 0) return;
        var minusEnd = s.IndexOf(' ', minus);
        var plusEnd = s.IndexOf(' ', plus);
        var oldPart = s.Substring(minus + 1, minusEnd - minus - 1);
        var newPart = s.Substring(plus + 1, plusEnd - plus - 1);
        ParsePair(oldPart, out oldStart, out oldCount);
        ParsePair(newPart, out newStart, out newCount);
    }

    private static void ParsePair(string s, out int start, out int count)
    {
        var comma = s.IndexOf(',');
        if (comma >= 0)
        {
            start = int.Parse(s.AsSpan(0, comma), System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture);
            count = int.Parse(s.AsSpan(comma + 1), System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture);
        }
        else
        {
            start = int.Parse(s.AsSpan(), System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture);
            count = 1;
        }
    }

    public Task<IReadOnlyList<FileTreeEntry>> GetFileTreeAsync(
        RepoLocation repo, CommitSha sha, string path, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        using var lg = new LibGit2Sharp.Repository(repo.Path);
        var c = lg.Lookup(sha.Value, LibGit2Sharp.ObjectType.Commit) as LibGit2Sharp.Commit
            ?? throw new InvalidOperationException($"Commit {sha} not found");

        LibGit2Sharp.Tree tree = c.Tree;
        if (!string.IsNullOrEmpty(path))
        {
            var entry = c[path]
                ?? throw new InvalidOperationException($"Path {path} not found at {sha}");
            if (entry.TargetType != LibGit2Sharp.TreeEntryTargetType.Tree)
                return Task.FromResult<IReadOnlyList<FileTreeEntry>>(Array.Empty<FileTreeEntry>());
            tree = (LibGit2Sharp.Tree)entry.Target;
        }

        var entries = tree.Select(t =>
        {
            var kind = t.TargetType switch
            {
                LibGit2Sharp.TreeEntryTargetType.Tree    => FileTreeKind.Tree,
                LibGit2Sharp.TreeEntryTargetType.GitLink => FileTreeKind.Submodule,
                _ when t.Mode == LibGit2Sharp.Mode.SymbolicLink => FileTreeKind.Symlink,
                _ => FileTreeKind.Blob
            };
            long? size = t.Target is LibGit2Sharp.Blob b ? b.Size : null;
            return new FileTreeEntry(
                Name: t.Name,
                FullPath: string.IsNullOrEmpty(path) ? t.Name : $"{path}/{t.Name}",
                Kind: kind,
                SizeBytes: size,
                ContainingCommit: sha);
        }).ToList();

        return Task.FromResult<IReadOnlyList<FileTreeEntry>>(entries);
    }
}
