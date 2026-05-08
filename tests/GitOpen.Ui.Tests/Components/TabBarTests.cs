using Bunit;
using FluentAssertions;
using GitOpen.Application.Workspaces;
using GitOpen.Domain.Repositories;
using GitOpen.Ui.Components;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using Xunit;

namespace GitOpen.Ui.Tests.Components;

public class TabBarTests : BunitContext
{
    [Fact]
    public void Renders_all_open_workspaces()
    {
        var mgr = Substitute.For<IWorkspaceManager>();
        var ws1 = new Workspace(new RepoLocation(RepoId.NewId(), "/a", "alpha"));
        var ws2 = new Workspace(new RepoLocation(RepoId.NewId(), "/b", "beta"));
        mgr.All.Returns(new[] { ws1, ws2 });
        Services.AddSingleton(mgr);

        var cut = Render<TabBar>();

        cut.Markup.Should().Contain("alpha").And.Contain("beta");
    }

    [Fact]
    public void Active_tab_has_active_class()
    {
        var mgr = Substitute.For<IWorkspaceManager>();
        var id = RepoId.NewId();
        mgr.All.Returns(new[] { new Workspace(new RepoLocation(id, "/a", "alpha")) });
        Services.AddSingleton(mgr);

        var cut = Render<TabBar>(p => p.Add(x => x.Active, id));

        cut.Find("button.tab.active").TextContent.Should().Contain("alpha");
    }
}
