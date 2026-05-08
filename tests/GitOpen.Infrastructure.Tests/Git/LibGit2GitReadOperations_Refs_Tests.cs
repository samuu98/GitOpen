using FluentAssertions;
using GitOpen.Domain.Repositories;
using GitOpen.Infrastructure.Git;
using GitOpen.Infrastructure.Tests.Helpers;
using LibGit2Sharp;
using Xunit;

namespace GitOpen.Infrastructure.Tests.Git;

public class LibGit2GitReadOperations_Refs_Tests
{
    private static RepoLocation Loc(RepoFixture f) => new(RepoId.NewId(), f.Path, "test");

    [Fact]
    public async Task GetBranchesAsync_lists_local_branches_with_current_marker()
    {
        using var f = RepoFixture.WithBranches();
        var sut = new LibGit2GitReadOperations();

        var branches = await sut.GetBranchesAsync(Loc(f), default);

        branches.Should().Contain(b => b.Name == "feature");
        branches.Where(b => !b.IsRemote).Where(b => b.IsCurrent).Should().HaveCount(1);
    }

    [Fact]
    public async Task GetTagsAsync_lists_tags()
    {
        using var f = RepoFixture.WithLinearHistory(1);
        using (var repo = new LibGit2Sharp.Repository(f.Path))
            repo.ApplyTag("v1.0");

        var sut = new LibGit2GitReadOperations();
        var tags = await sut.GetTagsAsync(Loc(f), default);

        tags.Should().ContainSingle(t => t.Name == "v1.0");
    }

    [Fact]
    public async Task GetRemotesAsync_returns_empty_when_none()
    {
        using var f = RepoFixture.WithLinearHistory(1);
        var sut = new LibGit2GitReadOperations();
        var remotes = await sut.GetRemotesAsync(Loc(f), default);
        remotes.Should().BeEmpty();
    }

    [Fact]
    public async Task GetStashesAsync_returns_empty_when_none()
    {
        using var f = RepoFixture.WithLinearHistory(1);
        var sut = new LibGit2GitReadOperations();
        var stashes = await sut.GetStashesAsync(Loc(f), default);
        stashes.Should().BeEmpty();
    }
}
