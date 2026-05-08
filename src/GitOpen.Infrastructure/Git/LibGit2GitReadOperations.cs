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
            await Task.Yield();
        }
    }

    public Task<IReadOnlyList<Branch>> GetBranchesAsync(RepoLocation repo, CancellationToken ct)
        => throw new NotImplementedException();

    public Task<IReadOnlyList<Tag>> GetTagsAsync(RepoLocation repo, CancellationToken ct)
        => throw new NotImplementedException();

    public Task<IReadOnlyList<Remote>> GetRemotesAsync(RepoLocation repo, CancellationToken ct)
        => throw new NotImplementedException();

    public Task<IReadOnlyList<Stash>> GetStashesAsync(RepoLocation repo, CancellationToken ct)
        => throw new NotImplementedException();

    public Task<DiffResult> GetDiffAsync(RepoLocation repo, DiffSpec spec, CancellationToken ct)
        => throw new NotImplementedException();

    public Task<IReadOnlyList<FileTreeEntry>> GetFileTreeAsync(RepoLocation repo, CommitSha sha, string path, CancellationToken ct)
        => throw new NotImplementedException();
}
