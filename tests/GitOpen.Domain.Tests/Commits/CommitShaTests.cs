using FluentAssertions;
using GitOpen.Domain.Commits;
using Xunit;

namespace GitOpen.Domain.Tests.Commits;

public class CommitShaTests
{
    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("abc")]              // too short
    [InlineData("0123456789abcdef0123456789abcdef0123456789abc")] // too long
    public void Constructor_rejects_invalid_input(string input)
    {
        var act = () => new CommitSha(input);
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void Constructor_lowercases_value()
    {
        var sha = new CommitSha("ABCDEF1234");
        sha.Value.Should().Be("abcdef1234");
    }

    [Fact]
    public void Short_returns_first_seven_by_default()
    {
        var sha = new CommitSha("abcdef1234567890");
        sha.Short().Should().Be("abcdef1");
    }

    [Fact]
    public void Short_with_explicit_length()
    {
        var sha = new CommitSha("abcdef1234567890");
        sha.Short(4).Should().Be("abcd");
    }

    [Fact]
    public void Equality_is_case_insensitive_via_normalisation()
    {
        var a = new CommitSha("ABC123DEF456");
        var b = new CommitSha("abc123def456");
        a.Should().Be(b);
    }
}
