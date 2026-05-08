using FluentAssertions;
using GitOpen.Application.Workspaces;
using GitOpen.Domain.Repositories;
using NSubstitute;
using Xunit;

namespace GitOpen.Application.Tests.Workspaces;

public class WorkspaceManagerTests
{
    [Fact]
    public async Task OpenAsync_adds_workspace_and_fires_event()
    {
        var registry = Substitute.For<IRepositoryRegistry>();
        registry.AddAsync("/x", Arg.Any<CancellationToken>())
            .Returns(new RepoLocation(RepoId.NewId(), "/x", "x"));
        var sut = new WorkspaceManager(registry);
        WorkspaceOpened? captured = null;
        sut.Opened += e => captured = e;

        var ws = await sut.OpenAsync("/x", default);

        sut.All.Should().ContainSingle();
        captured.Should().NotBeNull();
        captured!.Location.Id.Should().Be(ws.Location.Id);
    }

    [Fact]
    public async Task OpenAsync_returns_existing_when_path_already_open()
    {
        var registry = Substitute.For<IRepositoryRegistry>();
        var loc = new RepoLocation(RepoId.NewId(), "/x", "x");
        registry.AddAsync("/x", Arg.Any<CancellationToken>()).Returns(loc);
        var sut = new WorkspaceManager(registry);

        var ws1 = await sut.OpenAsync("/x", default);
        var ws2 = await sut.OpenAsync("/x", default);

        sut.All.Should().HaveCount(1);
        ws2.Should().BeSameAs(ws1);
    }

    [Fact]
    public async Task CloseAsync_removes_workspace_and_fires_event()
    {
        var registry = Substitute.For<IRepositoryRegistry>();
        var id = RepoId.NewId();
        registry.AddAsync("/x", Arg.Any<CancellationToken>())
            .Returns(new RepoLocation(id, "/x", "x"));
        var sut = new WorkspaceManager(registry);
        await sut.OpenAsync("/x", default);
        WorkspaceClosed? captured = null;
        sut.Closed += e => captured = e;

        await sut.CloseAsync(id, default);

        sut.All.Should().BeEmpty();
        captured!.Id.Should().Be(id);
    }
}
