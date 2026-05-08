using FluentAssertions;
using GitOpen.Domain.Repositories;
using GitOpen.Domain.Status;
using GitOpen.Infrastructure.Git;
using GitOpen.Infrastructure.Tests.Helpers;
using Xunit;

namespace GitOpen.Infrastructure.Tests.Git;

public class LibGit2GitReadOperations_Status_Tests
{
    private static RepoLocation Loc(RepoFixture f) => new(RepoId.NewId(), f.Path, "test");

    [Fact]
    public async Task GetStatusAsync_clean_after_commit()
    {
        using var f = RepoFixture.WithLinearHistory(1);
        var sut = new LibGit2GitReadOperations();

        var status = await sut.GetStatusAsync(Loc(f), default);

        status.Entries.Should().BeEmpty();
        status.HeadSha!.Value.Value.Should().Be(f.HeadSha);
        status.IsBare.Should().BeFalse();
        status.IsDetached.Should().BeFalse();
        (status.CurrentBranch == "master" || status.CurrentBranch == "main")
            .Should().BeTrue();
    }

    [Fact]
    public async Task GetStatusAsync_reports_untracked_file()
    {
        using var f = RepoFixture.WithLinearHistory(1);
        File.WriteAllText(System.IO.Path.Combine(f.Path, "new.txt"), "hi");
        var sut = new LibGit2GitReadOperations();

        var status = await sut.GetStatusAsync(Loc(f), default);

        status.Entries.Should().Contain(e =>
            e.Path == "new.txt" && e.WorkingTreeState == WorkingFileState.Untracked);
    }

    [Fact]
    public async Task GetStatusAsync_reports_modified_file()
    {
        using var f = RepoFixture.WithLinearHistory(1);
        File.WriteAllText(System.IO.Path.Combine(f.Path, "file_0.txt"), "changed");
        var sut = new LibGit2GitReadOperations();

        var status = await sut.GetStatusAsync(Loc(f), default);

        status.Entries.Should().Contain(e =>
            e.Path == "file_0.txt" && e.WorkingTreeState == WorkingFileState.Modified);
    }
}
