using FluentAssertions;
using GitOpen.Infrastructure.Persistence;
using GitOpen.Infrastructure.Tests.Helpers;
using Xunit;

namespace GitOpen.Infrastructure.Tests.Persistence;

public class WorkspacePersistenceTests
{
    [Fact]
    public async Task Roundtrip_paths()
    {
        using var db = InMemoryDb.CreateInMemory();
        var sut = new WorkspacePersistence(db);
        await sut.SaveOpenPathsAsync(new List<string> { "/a", "/b" }, default);

        var read = await sut.GetOpenPathsAsync(default);

        read.Should().Equal("/a", "/b");
    }
}
