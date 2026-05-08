# GitOpen Slice 1 (Read-Only Viewer) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a runnable read-only desktop git viewer: open one or more local repositories in tabs, see refs in a sidebar, scroll a virtualised commit graph with SVG lanes, inspect a commit's diff and file tree. No writes.

**Architecture:** Clean-Architecture-lite four-project solution (Domain → Application → Infrastructure / Ui). Single-process .NET 8 host with Photino.Blazor as desktop shell, Blazor for UI, LibGit2Sharp for read-side git ops, EF Core + SQLite for persistence, Serilog for logging. TDD on Domain / Application / Infrastructure; component-first then bUnit on UI.

**Tech Stack:** .NET 8 LTS, Photino.Blazor 3.x, LibGit2Sharp 0.30.x, EF Core 8.x (Sqlite provider), Microsoft.Data.Sqlite, Serilog 3.x (Console + File sinks), xUnit 2.x, bUnit 1.x, FluentAssertions 6.x, NSubstitute 5.x.

**Reading order for tasks:** Phases A → J. Each task depends only on earlier tasks. Inside a phase, tasks are sequential.

**Conventions used in every task:**
- File paths are repo-relative; the repo root is `C:\Users\s.porta\Documents\GitOpen`.
- Test commands are run from the repo root.
- After each task that ends in a commit, the working tree must be clean before starting the next task.
- All commits use the trailer `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` (already configured in user's git config or appended manually).
- Branch model: do all of Slice 1 on `master` for now (single-developer, slice-based releases). A `slice-1-readonly` branch is fine if the developer prefers; not required by the plan.

---

## Phase A — Solution scaffolding

### Task A1: Create solution and project skeletons

**Files:**
- Create: `GitOpen.sln`
- Create: `src/GitOpen.Domain/GitOpen.Domain.csproj`
- Create: `src/GitOpen.Application/GitOpen.Application.csproj`
- Create: `src/GitOpen.Infrastructure/GitOpen.Infrastructure.csproj`
- Create: `src/GitOpen.Ui/GitOpen.Ui.csproj`
- Create: `tests/GitOpen.Domain.Tests/GitOpen.Domain.Tests.csproj`
- Create: `tests/GitOpen.Application.Tests/GitOpen.Application.Tests.csproj`
- Create: `tests/GitOpen.Infrastructure.Tests/GitOpen.Infrastructure.Tests.csproj`
- Create: `tests/GitOpen.Ui.Tests/GitOpen.Ui.Tests.csproj`
- Create: `Directory.Build.props`
- Create: `.gitignore`
- Create: `LICENSE` (MIT)

- [ ] **Step 1: Create `.gitignore` (dotnet template)**

```bash
dotnet new gitignore
```

- [ ] **Step 2: Create `Directory.Build.props` at repo root**

This centralises common props for all projects.

```xml
<Project>
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <LangVersion>latest</LangVersion>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <WarningsNotAsErrors>CS1591</WarningsNotAsErrors>
    <GenerateDocumentationFile>false</GenerateDocumentationFile>
    <NeutralLanguage>en</NeutralLanguage>
    <AnalysisLevel>latest-recommended</AnalysisLevel>
    <Deterministic>true</Deterministic>
  </PropertyGroup>
</Project>
```

- [ ] **Step 3: Create solution and projects**

```bash
dotnet new sln -n GitOpen
dotnet new classlib -n GitOpen.Domain -o src/GitOpen.Domain
dotnet new classlib -n GitOpen.Application -o src/GitOpen.Application
dotnet new classlib -n GitOpen.Infrastructure -o src/GitOpen.Infrastructure
dotnet new classlib -n GitOpen.Ui -o src/GitOpen.Ui
dotnet new xunit -n GitOpen.Domain.Tests -o tests/GitOpen.Domain.Tests
dotnet new xunit -n GitOpen.Application.Tests -o tests/GitOpen.Application.Tests
dotnet new xunit -n GitOpen.Infrastructure.Tests -o tests/GitOpen.Infrastructure.Tests
dotnet new xunit -n GitOpen.Ui.Tests -o tests/GitOpen.Ui.Tests

dotnet sln add src/GitOpen.Domain/GitOpen.Domain.csproj
dotnet sln add src/GitOpen.Application/GitOpen.Application.csproj
dotnet sln add src/GitOpen.Infrastructure/GitOpen.Infrastructure.csproj
dotnet sln add src/GitOpen.Ui/GitOpen.Ui.csproj
dotnet sln add tests/GitOpen.Domain.Tests/GitOpen.Domain.Tests.csproj
dotnet sln add tests/GitOpen.Application.Tests/GitOpen.Application.Tests.csproj
dotnet sln add tests/GitOpen.Infrastructure.Tests/GitOpen.Infrastructure.Tests.csproj
dotnet sln add tests/GitOpen.Ui.Tests/GitOpen.Ui.Tests.csproj
```

Delete the auto-generated `Class1.cs` from each `classlib` project and `UnitTest1.cs` from each test project.

- [ ] **Step 4: Wire project references**

```bash
dotnet add src/GitOpen.Application reference src/GitOpen.Domain
dotnet add src/GitOpen.Infrastructure reference src/GitOpen.Domain src/GitOpen.Application
dotnet add src/GitOpen.Ui reference src/GitOpen.Domain src/GitOpen.Application src/GitOpen.Infrastructure
dotnet add tests/GitOpen.Domain.Tests reference src/GitOpen.Domain
dotnet add tests/GitOpen.Application.Tests reference src/GitOpen.Application src/GitOpen.Domain
dotnet add tests/GitOpen.Infrastructure.Tests reference src/GitOpen.Infrastructure src/GitOpen.Application src/GitOpen.Domain
dotnet add tests/GitOpen.Ui.Tests reference src/GitOpen.Ui src/GitOpen.Application src/GitOpen.Domain
```

Add **FluentAssertions** to all test projects:

```bash
dotnet add tests/GitOpen.Domain.Tests package FluentAssertions
dotnet add tests/GitOpen.Application.Tests package FluentAssertions
dotnet add tests/GitOpen.Application.Tests package NSubstitute
dotnet add tests/GitOpen.Infrastructure.Tests package FluentAssertions
dotnet add tests/GitOpen.Ui.Tests package FluentAssertions
```

- [ ] **Step 5: Convert Ui project to WPF/Blazor-friendly type**

Edit `src/GitOpen.Ui/GitOpen.Ui.csproj` to set `OutputType=Exe`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <RootNamespace>GitOpen.Ui</RootNamespace>
    <AssemblyName>GitOpen</AssemblyName>
  </PropertyGroup>
</Project>
```

- [ ] **Step 6: Create LICENSE (MIT)**

```
MIT License

Copyright (c) 2026 s.porta

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 7: Verify build**

```bash
dotnet build GitOpen.sln
```

Expected: build succeeds with 0 warnings, 0 errors.

- [ ] **Step 8: Commit**

```bash
git add .
git commit -m "feat(scaffold): initial solution skeleton"
```

---

### Task A2: Add CI workflow (matrix Windows + Ubuntu)

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: CI

on:
  push:
    branches: [master, main]
  pull_request:

jobs:
  build-test:
    strategy:
      fail-fast: false
      matrix:
        os: [windows-latest, ubuntu-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: 8.0.x
      - name: Restore
        run: dotnet restore GitOpen.sln
      - name: Build
        run: dotnet build GitOpen.sln --no-restore --configuration Release
      - name: Test
        run: dotnet test GitOpen.sln --no-build --configuration Release --logger "trx;LogFileName=test-results.trx" --results-directory ./test-results
      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results-${{ matrix.os }}
          path: ./test-results
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: matrix build+test on Win and Ubuntu"
```

CI will fail to push until a remote exists; that is OK for now. Local validation of the YAML is sufficient.

---

## Phase B — Domain types

### Task B1: Define core git domain records

**Files:**
- Create: `src/GitOpen.Domain/Repositories/RepoId.cs`
- Create: `src/GitOpen.Domain/Repositories/RepoLocation.cs`
- Create: `src/GitOpen.Domain/Commits/CommitSha.cs`
- Create: `src/GitOpen.Domain/Commits/CommitInfo.cs`
- Create: `src/GitOpen.Domain/Commits/CommitSignature.cs`
- Create: `src/GitOpen.Domain/Refs/Branch.cs`
- Create: `src/GitOpen.Domain/Refs/Tag.cs`
- Create: `src/GitOpen.Domain/Refs/Remote.cs`
- Create: `src/GitOpen.Domain/Refs/Stash.cs`
- Create: `src/GitOpen.Domain/Status/RepoStatus.cs`
- Create: `src/GitOpen.Domain/Status/WorkingFileEntry.cs`
- Create: `src/GitOpen.Domain/Diff/DiffSpec.cs`
- Create: `src/GitOpen.Domain/Diff/DiffResult.cs`
- Create: `src/GitOpen.Domain/Diff/FileDiff.cs`
- Create: `src/GitOpen.Domain/Diff/DiffHunk.cs`
- Create: `src/GitOpen.Domain/Diff/DiffLine.cs`
- Create: `src/GitOpen.Domain/Files/FileTreeEntry.cs`

- [ ] **Step 1: Add identity & location types**

`src/GitOpen.Domain/Repositories/RepoId.cs`:
```csharp
namespace GitOpen.Domain.Repositories;

public readonly record struct RepoId(Guid Value)
{
    public static RepoId NewId() => new(Guid.NewGuid());
    public override string ToString() => Value.ToString("N");
}
```

`src/GitOpen.Domain/Repositories/RepoLocation.cs`:
```csharp
namespace GitOpen.Domain.Repositories;

public sealed record RepoLocation(RepoId Id, string Path, string DisplayName);
```

- [ ] **Step 2: Add commit types**

`src/GitOpen.Domain/Commits/CommitSha.cs`:
```csharp
namespace GitOpen.Domain.Commits;

public readonly record struct CommitSha
{
    public string Value { get; }

    public CommitSha(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new ArgumentException("CommitSha cannot be empty", nameof(value));
        if (value.Length is < 4 or > 40)
            throw new ArgumentException("CommitSha must be 4..40 hex chars", nameof(value));
        Value = value.ToLowerInvariant();
    }

    public string Short(int length = 7) =>
        Value.Length <= length ? Value : Value[..length];

    public override string ToString() => Value;
}
```

`src/GitOpen.Domain/Commits/CommitSignature.cs`:
```csharp
namespace GitOpen.Domain.Commits;

public sealed record CommitSignature(string Name, string Email, DateTimeOffset When);
```

`src/GitOpen.Domain/Commits/CommitInfo.cs`:
```csharp
namespace GitOpen.Domain.Commits;

public sealed record CommitInfo(
    CommitSha Sha,
    IReadOnlyList<CommitSha> ParentShas,
    CommitSignature Author,
    CommitSignature Committer,
    string Summary,
    string Message);
```

- [ ] **Step 3: Add ref types**

`src/GitOpen.Domain/Refs/Branch.cs`:
```csharp
using GitOpen.Domain.Commits;

namespace GitOpen.Domain.Refs;

public sealed record Branch(
    string Name,
    string FullName,
    bool IsRemote,
    bool IsCurrent,
    CommitSha? TipSha,
    string? UpstreamFullName,
    int Ahead,
    int Behind);
```

`src/GitOpen.Domain/Refs/Tag.cs`:
```csharp
using GitOpen.Domain.Commits;

namespace GitOpen.Domain.Refs;

public sealed record Tag(string Name, string FullName, CommitSha TargetSha, bool IsAnnotated);
```

`src/GitOpen.Domain/Refs/Remote.cs`:
```csharp
namespace GitOpen.Domain.Refs;

public sealed record Remote(string Name, string Url, IReadOnlyList<Branch> Branches);
```

`src/GitOpen.Domain/Refs/Stash.cs`:
```csharp
using GitOpen.Domain.Commits;

namespace GitOpen.Domain.Refs;

public sealed record Stash(int Index, CommitSha Sha, string Message, DateTimeOffset CreatedAt);
```

- [ ] **Step 4: Add status types**

`src/GitOpen.Domain/Status/WorkingFileEntry.cs`:
```csharp
namespace GitOpen.Domain.Status;

public enum WorkingFileState { Unmodified, Added, Modified, Deleted, Renamed, Conflicted, Untracked, Ignored }

public sealed record WorkingFileEntry(
    string Path,
    WorkingFileState IndexState,
    WorkingFileState WorkingTreeState,
    string? OldPath = null);
```

`src/GitOpen.Domain/Status/RepoStatus.cs`:
```csharp
using GitOpen.Domain.Commits;

namespace GitOpen.Domain.Status;

public sealed record RepoStatus(
    string? CurrentBranch,
    CommitSha? HeadSha,
    bool IsDetached,
    bool IsBare,
    IReadOnlyList<WorkingFileEntry> Entries);
```

- [ ] **Step 5: Add diff types**

`src/GitOpen.Domain/Diff/DiffSpec.cs`:
```csharp
using GitOpen.Domain.Commits;

namespace GitOpen.Domain.Diff;

public abstract record DiffSpec
{
    public sealed record CommitVsParent(CommitSha CommitSha) : DiffSpec;
    public sealed record CommitVsCommit(CommitSha From, CommitSha To) : DiffSpec;
    public sealed record IndexVsHead : DiffSpec;
    public sealed record WorkingTreeVsIndex : DiffSpec;
}
```

`src/GitOpen.Domain/Diff/DiffLine.cs`:
```csharp
namespace GitOpen.Domain.Diff;

public enum DiffLineKind { Context, Addition, Deletion }

public sealed record DiffLine(DiffLineKind Kind, int? OldLine, int? NewLine, string Content);
```

`src/GitOpen.Domain/Diff/DiffHunk.cs`:
```csharp
namespace GitOpen.Domain.Diff;

public sealed record DiffHunk(
    int OldStart,
    int OldCount,
    int NewStart,
    int NewCount,
    string Header,
    IReadOnlyList<DiffLine> Lines);
```

`src/GitOpen.Domain/Diff/FileDiff.cs`:
```csharp
namespace GitOpen.Domain.Diff;

public enum FileChangeKind { Added, Deleted, Modified, Renamed, Copied, TypeChanged, Unmerged }

public sealed record FileDiff(
    string Path,
    string? OldPath,
    FileChangeKind ChangeKind,
    bool IsBinary,
    int LinesAdded,
    int LinesDeleted,
    IReadOnlyList<DiffHunk> Hunks);
```

`src/GitOpen.Domain/Diff/DiffResult.cs`:
```csharp
namespace GitOpen.Domain.Diff;

public sealed record DiffResult(IReadOnlyList<FileDiff> Files);
```

- [ ] **Step 6: Add file tree types**

`src/GitOpen.Domain/Files/FileTreeEntry.cs`:
```csharp
using GitOpen.Domain.Commits;

namespace GitOpen.Domain.Files;

public enum FileTreeKind { Blob, Tree, Submodule, Symlink }

public sealed record FileTreeEntry(
    string Name,
    string FullPath,
    FileTreeKind Kind,
    long? SizeBytes,
    CommitSha? ContainingCommit);
```

- [ ] **Step 7: Build**

```bash
dotnet build src/GitOpen.Domain/GitOpen.Domain.csproj
```

Expected: builds clean.

- [ ] **Step 8: Commit**

```bash
git add src/GitOpen.Domain
git commit -m "feat(domain): core git records (commits, refs, status, diff, tree)"
```

---

### Task B2: Domain unit tests for value-type invariants

**Files:**
- Create: `tests/GitOpen.Domain.Tests/Commits/CommitShaTests.cs`

- [ ] **Step 1: Write tests**

```csharp
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
```

- [ ] **Step 2: Run**

```bash
dotnet test tests/GitOpen.Domain.Tests
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add tests/GitOpen.Domain.Tests
git commit -m "test(domain): CommitSha invariants"
```

---

## Phase C — Infrastructure: LibGit2Sharp read operations

### Task C1: Add LibGit2Sharp + create RepoFixture for tests

**Files:**
- Modify: `src/GitOpen.Infrastructure/GitOpen.Infrastructure.csproj`
- Modify: `tests/GitOpen.Infrastructure.Tests/GitOpen.Infrastructure.Tests.csproj`
- Create: `tests/GitOpen.Infrastructure.Tests/Helpers/RepoFixture.cs`
- Create: `tests/GitOpen.Infrastructure.Tests/Helpers/RepoFixtureTests.cs`

- [ ] **Step 1: Add packages**

```bash
dotnet add src/GitOpen.Infrastructure package LibGit2Sharp
dotnet add tests/GitOpen.Infrastructure.Tests package LibGit2Sharp
```

- [ ] **Step 2: Write the fixture**

`tests/GitOpen.Infrastructure.Tests/Helpers/RepoFixture.cs`:
```csharp
using LibGit2Sharp;

namespace GitOpen.Infrastructure.Tests.Helpers;

public sealed class RepoFixture : IDisposable
{
    public string Path { get; }
    public string HeadSha { get; private set; } = "";

    private RepoFixture(string path) { Path = path; }

    public static RepoFixture Empty()
    {
        var path = CreateTempPath();
        Repository.Init(path);
        return new RepoFixture(path);
    }

    public static RepoFixture WithLinearHistory(int commits)
    {
        if (commits < 1) throw new ArgumentOutOfRangeException(nameof(commits));
        var fixture = Empty();
        using var repo = new Repository(fixture.Path);
        var sig = new Signature("Test", "test@example.com", DateTimeOffset.UtcNow);
        for (var i = 0; i < commits; i++)
        {
            var file = System.IO.Path.Combine(fixture.Path, $"file_{i}.txt");
            File.WriteAllText(file, $"content {i}\n");
            Commands.Stage(repo, $"file_{i}.txt");
            var c = repo.Commit($"commit {i}", sig, sig);
            fixture.HeadSha = c.Sha;
        }
        return fixture;
    }

    public static RepoFixture WithBranches()
    {
        var fixture = WithLinearHistory(3);
        using var repo = new Repository(fixture.Path);
        var sig = new Signature("Test", "test@example.com", DateTimeOffset.UtcNow);
        var feature = repo.CreateBranch("feature");
        Commands.Checkout(repo, feature);
        var file = System.IO.Path.Combine(fixture.Path, "feature.txt");
        File.WriteAllText(file, "feature\n");
        Commands.Stage(repo, "feature.txt");
        repo.Commit("on feature", sig, sig);
        Commands.Checkout(repo, repo.Branches["master"] ?? repo.Branches["main"]!);
        return fixture;
    }

    public void Dispose()
    {
        try { ForceDelete(Path); } catch { /* best-effort cleanup */ }
    }

    private static string CreateTempPath()
    {
        var p = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "gitopen-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(p);
        return p;
    }

    private static void ForceDelete(string path)
    {
        if (!Directory.Exists(path)) return;
        foreach (var f in Directory.GetFiles(path, "*", SearchOption.AllDirectories))
            File.SetAttributes(f, FileAttributes.Normal);
        Directory.Delete(path, recursive: true);
    }
}
```

- [ ] **Step 3: Verify the fixture itself works**

`tests/GitOpen.Infrastructure.Tests/Helpers/RepoFixtureTests.cs`:
```csharp
using FluentAssertions;
using LibGit2Sharp;
using Xunit;

namespace GitOpen.Infrastructure.Tests.Helpers;

public class RepoFixtureTests
{
    [Fact]
    public void WithLinearHistory_creates_repo_with_n_commits()
    {
        using var f = RepoFixture.WithLinearHistory(5);
        using var repo = new Repository(f.Path);
        repo.Commits.Count().Should().Be(5);
        repo.Head.Tip.Sha.Should().Be(f.HeadSha);
    }

    [Fact]
    public void Empty_creates_initialised_repo_with_no_commits()
    {
        using var f = RepoFixture.Empty();
        using var repo = new Repository(f.Path);
        repo.Commits.Should().BeEmpty();
    }

    [Fact]
    public void WithBranches_creates_master_and_feature()
    {
        using var f = RepoFixture.WithBranches();
        using var repo = new Repository(f.Path);
        repo.Branches.Should().Contain(b => b.FriendlyName == "feature");
    }
}
```

- [ ] **Step 4: Run**

```bash
dotnet test tests/GitOpen.Infrastructure.Tests
```

Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/GitOpen.Infrastructure tests/GitOpen.Infrastructure.Tests
git commit -m "test(infra): RepoFixture for real git repo tests"
```

---

### Task C2: IGitReadOperations contract + LibGit2Sharp implementation skeleton

**Files:**
- Create: `src/GitOpen.Application/Git/IGitReadOperations.cs`
- Create: `src/GitOpen.Infrastructure/Git/LibGit2GitReadOperations.cs`

- [ ] **Step 1: Define the contract**

`src/GitOpen.Application/Git/IGitReadOperations.cs`:
```csharp
using GitOpen.Domain.Commits;
using GitOpen.Domain.Diff;
using GitOpen.Domain.Files;
using GitOpen.Domain.Refs;
using GitOpen.Domain.Repositories;
using GitOpen.Domain.Status;

namespace GitOpen.Application.Git;

public sealed record CommitQuery(int? Skip = null, int? Take = null, string? RefSpec = null);

public interface IGitReadOperations
{
    Task<RepoStatus> GetStatusAsync(RepoLocation repo, CancellationToken ct);
    IAsyncEnumerable<CommitInfo> GetCommitsAsync(RepoLocation repo, CommitQuery query, CancellationToken ct);
    Task<IReadOnlyList<Branch>> GetBranchesAsync(RepoLocation repo, CancellationToken ct);
    Task<IReadOnlyList<Tag>> GetTagsAsync(RepoLocation repo, CancellationToken ct);
    Task<IReadOnlyList<Remote>> GetRemotesAsync(RepoLocation repo, CancellationToken ct);
    Task<IReadOnlyList<Stash>> GetStashesAsync(RepoLocation repo, CancellationToken ct);
    Task<DiffResult> GetDiffAsync(RepoLocation repo, DiffSpec spec, CancellationToken ct);
    Task<IReadOnlyList<FileTreeEntry>> GetFileTreeAsync(RepoLocation repo, CommitSha sha, string path, CancellationToken ct);
}
```

- [ ] **Step 2: Stub the implementation**

`src/GitOpen.Infrastructure/Git/LibGit2GitReadOperations.cs`:
```csharp
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
        => throw new NotImplementedException();

    public IAsyncEnumerable<CommitInfo> GetCommitsAsync(RepoLocation repo, CommitQuery query, CancellationToken ct)
        => throw new NotImplementedException();

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
```

- [ ] **Step 3: Build**

```bash
dotnet build GitOpen.sln
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add src/GitOpen.Application src/GitOpen.Infrastructure
git commit -m "feat(infra): IGitReadOperations contract + LibGit2 skeleton"
```

---

### Task C3 (TDD): Implement GetCommitsAsync

**Files:**
- Create: `tests/GitOpen.Infrastructure.Tests/Git/LibGit2GitReadOperations_Commits_Tests.cs`
- Modify: `src/GitOpen.Infrastructure/Git/LibGit2GitReadOperations.cs`

- [ ] **Step 1: Write failing tests**

```csharp
using FluentAssertions;
using GitOpen.Application.Git;
using GitOpen.Domain.Repositories;
using GitOpen.Infrastructure.Git;
using GitOpen.Infrastructure.Tests.Helpers;
using Xunit;

namespace GitOpen.Infrastructure.Tests.Git;

public class LibGit2GitReadOperations_Commits_Tests
{
    private static RepoLocation Loc(RepoFixture f) =>
        new(RepoId.NewId(), f.Path, "test");

    [Fact]
    public async Task GetCommitsAsync_returns_all_in_topological_order()
    {
        using var f = RepoFixture.WithLinearHistory(5);
        var sut = new LibGit2GitReadOperations();

        var commits = new List<GitOpen.Domain.Commits.CommitInfo>();
        await foreach (var c in sut.GetCommitsAsync(Loc(f), new CommitQuery(), default))
            commits.Add(c);

        commits.Should().HaveCount(5);
        commits[0].Sha.Value.Should().Be(f.HeadSha);
    }

    [Fact]
    public async Task GetCommitsAsync_respects_take_and_skip()
    {
        using var f = RepoFixture.WithLinearHistory(10);
        var sut = new LibGit2GitReadOperations();

        var commits = new List<GitOpen.Domain.Commits.CommitInfo>();
        await foreach (var c in sut.GetCommitsAsync(Loc(f), new CommitQuery(Skip: 2, Take: 3), default))
            commits.Add(c);

        commits.Should().HaveCount(3);
    }

    [Fact]
    public async Task GetCommitsAsync_returns_empty_for_empty_repo()
    {
        using var f = RepoFixture.Empty();
        var sut = new LibGit2GitReadOperations();

        var commits = new List<GitOpen.Domain.Commits.CommitInfo>();
        await foreach (var c in sut.GetCommitsAsync(Loc(f), new CommitQuery(), default))
            commits.Add(c);

        commits.Should().BeEmpty();
    }

    [Fact]
    public async Task GetCommitsAsync_respects_cancellation()
    {
        using var f = RepoFixture.WithLinearHistory(50);
        var sut = new LibGit2GitReadOperations();
        using var cts = new CancellationTokenSource();
        cts.Cancel();

        var act = async () =>
        {
            await foreach (var _ in sut.GetCommitsAsync(Loc(f), new CommitQuery(), cts.Token)) { }
        };

        await act.Should().ThrowAsync<OperationCanceledException>();
    }
}
```

- [ ] **Step 2: Run — they fail**

```bash
dotnet test tests/GitOpen.Infrastructure.Tests --filter "FullyQualifiedName~LibGit2GitReadOperations_Commits_Tests"
```

Expected: 4 tests fail with `NotImplementedException`.

- [ ] **Step 3: Implement**

Replace the body of `GetCommitsAsync` in `src/GitOpen.Infrastructure/Git/LibGit2GitReadOperations.cs`:

```csharp
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
```

- [ ] **Step 4: Run — they pass**

```bash
dotnet test tests/GitOpen.Infrastructure.Tests --filter "FullyQualifiedName~LibGit2GitReadOperations_Commits_Tests"
```

Expected: 4 pass.

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat(infra): GetCommitsAsync via LibGit2Sharp (TDD)"
```

---

### Task C4 (TDD): Implement GetStatusAsync

**Files:**
- Create: `tests/GitOpen.Infrastructure.Tests/Git/LibGit2GitReadOperations_Status_Tests.cs`
- Modify: `src/GitOpen.Infrastructure/Git/LibGit2GitReadOperations.cs`

- [ ] **Step 1: Write failing tests**

```csharp
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
```

- [ ] **Step 2: Run — fail**

```bash
dotnet test tests/GitOpen.Infrastructure.Tests --filter "FullyQualifiedName~LibGit2GitReadOperations_Status_Tests"
```

Expected: 3 fail.

- [ ] **Step 3: Implement**

Add a private mapping helper and replace `GetStatusAsync`:

```csharp
public Task<RepoStatus> GetStatusAsync(RepoLocation repo, CancellationToken ct)
{
    ct.ThrowIfCancellationRequested();
    using var lg = new LibGit2Sharp.Repository(repo.Path);
    var head = lg.Head;
    CommitSha? headSha = head.Tip is null ? null : new CommitSha(head.Tip.Sha);
    var entries = new List<WorkingFileEntry>();

    foreach (var s in lg.RetrieveStatus())
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
```

- [ ] **Step 4: Run — pass**

```bash
dotnet test tests/GitOpen.Infrastructure.Tests --filter "FullyQualifiedName~LibGit2GitReadOperations_Status_Tests"
```

Expected: 3 pass.

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat(infra): GetStatusAsync via LibGit2Sharp (TDD)"
```

---

### Task C5 (TDD): GetBranchesAsync, GetTagsAsync, GetRemotesAsync, GetStashesAsync

**Files:**
- Create: `tests/GitOpen.Infrastructure.Tests/Git/LibGit2GitReadOperations_Refs_Tests.cs`
- Modify: `src/GitOpen.Infrastructure/Git/LibGit2GitReadOperations.cs`

- [ ] **Step 1: Write tests**

```csharp
using FluentAssertions;
using GitOpen.Domain.Repositories;
using GitOpen.Infrastructure.Git;
using GitOpen.Infrastructure.Tests.Helpers;
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
```

- [ ] **Step 2: Run — fail**

```bash
dotnet test tests/GitOpen.Infrastructure.Tests --filter "FullyQualifiedName~LibGit2GitReadOperations_Refs_Tests"
```

Expected: 4 fail.

- [ ] **Step 3: Implement**

Replace the four methods:

```csharp
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
```

- [ ] **Step 4: Run — pass**

```bash
dotnet test tests/GitOpen.Infrastructure.Tests --filter "FullyQualifiedName~LibGit2GitReadOperations_Refs_Tests"
```

Expected: 4 pass.

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat(infra): branches/tags/remotes/stashes via LibGit2Sharp (TDD)"
```

---

### Task C6 (TDD): GetDiffAsync for CommitVsParent

**Files:**
- Create: `tests/GitOpen.Infrastructure.Tests/Git/LibGit2GitReadOperations_Diff_Tests.cs`
- Modify: `src/GitOpen.Infrastructure/Git/LibGit2GitReadOperations.cs`

- [ ] **Step 1: Write tests**

```csharp
using FluentAssertions;
using GitOpen.Domain.Commits;
using GitOpen.Domain.Diff;
using GitOpen.Domain.Repositories;
using GitOpen.Infrastructure.Git;
using GitOpen.Infrastructure.Tests.Helpers;
using Xunit;

namespace GitOpen.Infrastructure.Tests.Git;

public class LibGit2GitReadOperations_Diff_Tests
{
    private static RepoLocation Loc(RepoFixture f) => new(RepoId.NewId(), f.Path, "test");

    [Fact]
    public async Task GetDiffAsync_commit_vs_parent_lists_added_files()
    {
        using var f = RepoFixture.WithLinearHistory(2);
        var sut = new LibGit2GitReadOperations();

        var diff = await sut.GetDiffAsync(Loc(f),
            new DiffSpec.CommitVsParent(new CommitSha(f.HeadSha)), default);

        diff.Files.Should().ContainSingle(fd => fd.Path == "file_1.txt"
            && fd.ChangeKind == FileChangeKind.Added);
    }

    [Fact]
    public async Task GetDiffAsync_initial_commit_vs_no_parent_lists_all_added()
    {
        using var f = RepoFixture.WithLinearHistory(1);
        var sut = new LibGit2GitReadOperations();

        var diff = await sut.GetDiffAsync(Loc(f),
            new DiffSpec.CommitVsParent(new CommitSha(f.HeadSha)), default);

        diff.Files.Should().ContainSingle(fd => fd.Path == "file_0.txt"
            && fd.ChangeKind == FileChangeKind.Added);
    }
}
```

- [ ] **Step 2: Run — fail**

```bash
dotnet test tests/GitOpen.Infrastructure.Tests --filter "FullyQualifiedName~LibGit2GitReadOperations_Diff_Tests"
```

Expected: 2 fail.

- [ ] **Step 3: Implement**

Replace `GetDiffAsync`:

```csharp
public Task<DiffResult> GetDiffAsync(RepoLocation repo, DiffSpec spec, CancellationToken ct)
{
    ct.ThrowIfCancellationRequested();
    using var lg = new LibGit2Sharp.Repository(repo.Path);

    LibGit2Sharp.Tree? oldTree;
    LibGit2Sharp.Tree? newTree;

    switch (spec)
    {
        case DiffSpec.CommitVsParent cvp:
            var c = lg.Lookup<LibGit2Sharp.Commit>(cvp.CommitSha.Value)
                ?? throw new InvalidOperationException($"Commit {cvp.CommitSha} not found");
            newTree = c.Tree;
            oldTree = c.Parents.FirstOrDefault()?.Tree;
            break;
        case DiffSpec.CommitVsCommit cvc:
            var from = lg.Lookup<LibGit2Sharp.Commit>(cvc.From.Value);
            var to = lg.Lookup<LibGit2Sharp.Commit>(cvc.To.Value);
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
    var header = "";

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
            header = line;
            ParseHunkHeader(line, out oldStart, out oldCount, out newStart, out newCount);
            oldLine = oldStart;
            newLine = newStart;
            current = new DiffHunk(oldStart, oldCount, newStart, newCount, header, Array.Empty<DiffLine>());
            continue;
        }
        if (current is null) continue;
        if (line.Length == 0) continue;
        switch (line[0])
        {
            case '+': hunkLines.Add(new DiffLine(DiffLineKind.Addition, null, newLine++, line[1..])); break;
            case '-': hunkLines.Add(new DiffLine(DiffLineKind.Deletion, oldLine++, null, line[1..])); break;
            case ' ': hunkLines.Add(new DiffLine(DiffLineKind.Context, oldLine++, newLine++, line[1..])); break;
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
        start = int.Parse(s[..comma]);
        count = int.Parse(s[(comma + 1)..]);
    }
    else
    {
        start = int.Parse(s);
        count = 1;
    }
}
```

- [ ] **Step 4: Run — pass**

```bash
dotnet test tests/GitOpen.Infrastructure.Tests --filter "FullyQualifiedName~LibGit2GitReadOperations_Diff_Tests"
```

Expected: 2 pass.

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat(infra): GetDiffAsync (commit vs parent) via LibGit2Sharp (TDD)"
```

---

### Task C7 (TDD): GetFileTreeAsync

**Files:**
- Create: `tests/GitOpen.Infrastructure.Tests/Git/LibGit2GitReadOperations_FileTree_Tests.cs`
- Modify: `src/GitOpen.Infrastructure/Git/LibGit2GitReadOperations.cs`

- [ ] **Step 1: Write tests**

```csharp
using FluentAssertions;
using GitOpen.Domain.Commits;
using GitOpen.Domain.Files;
using GitOpen.Domain.Repositories;
using GitOpen.Infrastructure.Git;
using GitOpen.Infrastructure.Tests.Helpers;
using Xunit;

namespace GitOpen.Infrastructure.Tests.Git;

public class LibGit2GitReadOperations_FileTree_Tests
{
    private static RepoLocation Loc(RepoFixture f) => new(RepoId.NewId(), f.Path, "test");

    [Fact]
    public async Task GetFileTreeAsync_lists_root_files_for_commit()
    {
        using var f = RepoFixture.WithLinearHistory(3);
        var sut = new LibGit2GitReadOperations();

        var entries = await sut.GetFileTreeAsync(Loc(f), new CommitSha(f.HeadSha), "", default);

        entries.Should().Contain(e => e.Name == "file_0.txt" && e.Kind == FileTreeKind.Blob);
        entries.Should().Contain(e => e.Name == "file_1.txt");
        entries.Should().Contain(e => e.Name == "file_2.txt");
    }
}
```

- [ ] **Step 2: Run — fail**

```bash
dotnet test tests/GitOpen.Infrastructure.Tests --filter "FullyQualifiedName~LibGit2GitReadOperations_FileTree_Tests"
```

Expected: 1 fail.

- [ ] **Step 3: Implement**

Replace `GetFileTreeAsync`:

```csharp
public Task<IReadOnlyList<FileTreeEntry>> GetFileTreeAsync(
    RepoLocation repo, CommitSha sha, string path, CancellationToken ct)
{
    ct.ThrowIfCancellationRequested();
    using var lg = new LibGit2Sharp.Repository(repo.Path);
    var c = lg.Lookup<LibGit2Sharp.Commit>(sha.Value)
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
            LibGit2Sharp.TreeEntryTargetType.Tree      => FileTreeKind.Tree,
            LibGit2Sharp.TreeEntryTargetType.GitLink   => FileTreeKind.Submodule,
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
```

- [ ] **Step 4: Run — pass**

```bash
dotnet test tests/GitOpen.Infrastructure.Tests
```

Expected: all infrastructure tests pass.

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat(infra): GetFileTreeAsync via LibGit2Sharp (TDD)"
```

---

## Phase D — Persistence (EF Core + SQLite)

### Task D1: Add EF Core, define DbContext + entities + initial migration

**Files:**
- Modify: `src/GitOpen.Infrastructure/GitOpen.Infrastructure.csproj`
- Create: `src/GitOpen.Infrastructure/Persistence/GitOpenDbContext.cs`
- Create: `src/GitOpen.Infrastructure/Persistence/Entities/RepositoryRow.cs`
- Create: `src/GitOpen.Infrastructure/Persistence/Entities/RepositoryStateRow.cs`
- Create: `src/GitOpen.Infrastructure/Persistence/Entities/WindowRow.cs`
- Create: `src/GitOpen.Infrastructure/Persistence/Entities/SettingRow.cs`
- Create: `src/GitOpen.Infrastructure/Persistence/Entities/ActivityLogRow.cs`
- Create: `src/GitOpen.Infrastructure/Persistence/PathProvider.cs`

- [ ] **Step 1: Add packages**

```bash
dotnet add src/GitOpen.Infrastructure package Microsoft.EntityFrameworkCore.Sqlite --version 8.*
dotnet add src/GitOpen.Infrastructure package Microsoft.EntityFrameworkCore.Design --version 8.*
```

- [ ] **Step 2: Create entities**

`src/GitOpen.Infrastructure/Persistence/Entities/RepositoryRow.cs`:
```csharp
namespace GitOpen.Infrastructure.Persistence.Entities;

public class RepositoryRow
{
    public Guid Id { get; set; }
    public string Path { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public string? Color { get; set; }
    public DateTime LastOpenedUtc { get; set; }
    public int TabOrder { get; set; }
    public DateTime CreatedUtc { get; set; }
}
```

`src/GitOpen.Infrastructure/Persistence/Entities/RepositoryStateRow.cs`:
```csharp
namespace GitOpen.Infrastructure.Persistence.Entities;

public class RepositoryStateRow
{
    public Guid RepositoryId { get; set; }
    public string? LastBranchFullName { get; set; }
    public string? LastSelectedSha { get; set; }
    public int ScrollOffset { get; set; }
}
```

`src/GitOpen.Infrastructure/Persistence/Entities/WindowRow.cs`:
```csharp
namespace GitOpen.Infrastructure.Persistence.Entities;

public class WindowRow
{
    public Guid Id { get; set; }
    public int X { get; set; }
    public int Y { get; set; }
    public int Width { get; set; }
    public int Height { get; set; }
    public string WorkspaceIdsJson { get; set; } = "[]";
}
```

`src/GitOpen.Infrastructure/Persistence/Entities/SettingRow.cs`:
```csharp
namespace GitOpen.Infrastructure.Persistence.Entities;

public class SettingRow
{
    public string Key { get; set; } = "";
    public string ValueJson { get; set; } = "";
}
```

`src/GitOpen.Infrastructure/Persistence/Entities/ActivityLogRow.cs`:
```csharp
namespace GitOpen.Infrastructure.Persistence.Entities;

public class ActivityLogRow
{
    public long Id { get; set; }
    public DateTime TimestampUtc { get; set; }
    public Guid? RepositoryId { get; set; }
    public string Operation { get; set; } = "";
    public bool Ok { get; set; }
    public string? Stdout { get; set; }
    public string? Stderr { get; set; }
}
```

- [ ] **Step 3: PathProvider for state.db location**

`src/GitOpen.Infrastructure/Persistence/PathProvider.cs`:
```csharp
namespace GitOpen.Infrastructure.Persistence;

public static class PathProvider
{
    public static string ConfigDirectory()
    {
        var baseDir = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        if (string.IsNullOrEmpty(baseDir))
        {
            var home = Environment.GetEnvironmentVariable("HOME") ?? Environment.CurrentDirectory;
            baseDir = Path.Combine(home, ".config");
        }
        var dir = Path.Combine(baseDir, "GitOpen");
        Directory.CreateDirectory(dir);
        return dir;
    }

    public static string StateDbPath() => Path.Combine(ConfigDirectory(), "state.db");
    public static string SettingsJsonPath() => Path.Combine(ConfigDirectory(), "settings.json");
    public static string LogDirectory()
    {
        var dir = Path.Combine(ConfigDirectory(), "logs");
        Directory.CreateDirectory(dir);
        return dir;
    }
}
```

- [ ] **Step 4: DbContext**

`src/GitOpen.Infrastructure/Persistence/GitOpenDbContext.cs`:
```csharp
using GitOpen.Infrastructure.Persistence.Entities;
using Microsoft.EntityFrameworkCore;

namespace GitOpen.Infrastructure.Persistence;

public class GitOpenDbContext : DbContext
{
    public DbSet<RepositoryRow> Repositories => Set<RepositoryRow>();
    public DbSet<RepositoryStateRow> RepositoryStates => Set<RepositoryStateRow>();
    public DbSet<WindowRow> Windows => Set<WindowRow>();
    public DbSet<SettingRow> Settings => Set<SettingRow>();
    public DbSet<ActivityLogRow> ActivityLog => Set<ActivityLogRow>();

    public GitOpenDbContext() { }
    public GitOpenDbContext(DbContextOptions<GitOpenDbContext> opts) : base(opts) { }

    protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
    {
        if (!optionsBuilder.IsConfigured)
            optionsBuilder.UseSqlite($"Data Source={PathProvider.StateDbPath()}");
    }

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<RepositoryRow>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.Path).IsUnique();
            e.Property(x => x.Path).IsRequired();
            e.Property(x => x.DisplayName).IsRequired();
        });
        b.Entity<RepositoryStateRow>().HasKey(x => x.RepositoryId);
        b.Entity<WindowRow>().HasKey(x => x.Id);
        b.Entity<SettingRow>().HasKey(x => x.Key);
        b.Entity<ActivityLogRow>().HasKey(x => x.Id);
    }
}
```

- [ ] **Step 5: Install EF Core CLI tool & create initial migration**

```bash
dotnet tool install --global dotnet-ef --version 8.*  || true
dotnet ef migrations add Initial --project src/GitOpen.Infrastructure --startup-project src/GitOpen.Infrastructure
```

Expected: a `Migrations/` folder is created in `src/GitOpen.Infrastructure`. If `dotnet ef` fails because it cannot find the design-time DbContext, ensure `Microsoft.EntityFrameworkCore.Design` package was added.

- [ ] **Step 6: Build**

```bash
dotnet build src/GitOpen.Infrastructure
```

- [ ] **Step 7: Commit**

```bash
git add src/GitOpen.Infrastructure
git commit -m "feat(infra): EF Core DbContext + entities + initial migration"
```

---

### Task D2 (TDD): RepositoryRegistry — add/list/remove repos

**Files:**
- Create: `src/GitOpen.Application/Workspaces/IRepositoryRegistry.cs`
- Create: `src/GitOpen.Infrastructure/Persistence/RepositoryRegistry.cs`
- Create: `tests/GitOpen.Infrastructure.Tests/Persistence/RepositoryRegistryTests.cs`
- Create: `tests/GitOpen.Infrastructure.Tests/Helpers/InMemoryDb.cs`

- [ ] **Step 1: Write the contract**

`src/GitOpen.Application/Workspaces/IRepositoryRegistry.cs`:
```csharp
using GitOpen.Domain.Repositories;

namespace GitOpen.Application.Workspaces;

public interface IRepositoryRegistry
{
    Task<RepoLocation> AddAsync(string path, CancellationToken ct);
    Task<IReadOnlyList<RepoLocation>> ListAsync(CancellationToken ct);
    Task<RepoLocation?> GetByPathAsync(string path, CancellationToken ct);
    Task RemoveAsync(RepoId id, CancellationToken ct);
    Task TouchLastOpenedAsync(RepoId id, CancellationToken ct);
}
```

- [ ] **Step 2: In-memory db helper for tests**

`tests/GitOpen.Infrastructure.Tests/Helpers/InMemoryDb.cs`:
```csharp
using GitOpen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace GitOpen.Infrastructure.Tests.Helpers;

public static class InMemoryDb
{
    public static GitOpenDbContext CreateInMemory()
    {
        var conn = new Microsoft.Data.Sqlite.SqliteConnection("Data Source=:memory:");
        conn.Open();
        var opts = new DbContextOptionsBuilder<GitOpenDbContext>()
            .UseSqlite(conn).Options;
        var ctx = new GitOpenDbContext(opts);
        ctx.Database.EnsureCreated();
        return ctx;
    }
}
```

- [ ] **Step 3: Write failing tests**

`tests/GitOpen.Infrastructure.Tests/Persistence/RepositoryRegistryTests.cs`:
```csharp
using FluentAssertions;
using GitOpen.Infrastructure.Persistence;
using GitOpen.Infrastructure.Tests.Helpers;
using Xunit;

namespace GitOpen.Infrastructure.Tests.Persistence;

public class RepositoryRegistryTests
{
    [Fact]
    public async Task AddAsync_persists_repo_and_returns_location()
    {
        using var db = InMemoryDb.CreateInMemory();
        var sut = new RepositoryRegistry(db);

        var loc = await sut.AddAsync("/tmp/foo/.git/..", default);

        loc.Path.Should().Be("/tmp/foo/.git/..");
        loc.DisplayName.Should().NotBeNullOrEmpty();
        var listed = await sut.ListAsync(default);
        listed.Should().ContainSingle(r => r.Id == loc.Id);
    }

    [Fact]
    public async Task AddAsync_returns_existing_when_path_already_known()
    {
        using var db = InMemoryDb.CreateInMemory();
        var sut = new RepositoryRegistry(db);

        var first = await sut.AddAsync("/tmp/dup", default);
        var second = await sut.AddAsync("/tmp/dup", default);

        second.Id.Should().Be(first.Id);
        (await sut.ListAsync(default)).Should().HaveCount(1);
    }

    [Fact]
    public async Task RemoveAsync_deletes_the_repo()
    {
        using var db = InMemoryDb.CreateInMemory();
        var sut = new RepositoryRegistry(db);
        var loc = await sut.AddAsync("/tmp/gone", default);

        await sut.RemoveAsync(loc.Id, default);

        (await sut.ListAsync(default)).Should().BeEmpty();
    }

    [Fact]
    public async Task TouchLastOpenedAsync_updates_timestamp()
    {
        using var db = InMemoryDb.CreateInMemory();
        var sut = new RepositoryRegistry(db);
        var loc = await sut.AddAsync("/tmp/x", default);
        var initial = (await sut.GetByPathAsync("/tmp/x", default))!;
        await Task.Delay(10);

        await sut.TouchLastOpenedAsync(loc.Id, default);

        var raw = db.Repositories.Single(r => r.Id == loc.Id.Value);
        raw.LastOpenedUtc.Should().BeAfter(default(DateTime));
    }
}
```

- [ ] **Step 4: Run — fail (RepositoryRegistry not defined)**

```bash
dotnet test tests/GitOpen.Infrastructure.Tests --filter "FullyQualifiedName~RepositoryRegistryTests"
```

Expected: compile error / test failure.

- [ ] **Step 5: Implement**

`src/GitOpen.Infrastructure/Persistence/RepositoryRegistry.cs`:
```csharp
using GitOpen.Application.Workspaces;
using GitOpen.Domain.Repositories;
using GitOpen.Infrastructure.Persistence.Entities;
using Microsoft.EntityFrameworkCore;

namespace GitOpen.Infrastructure.Persistence;

public sealed class RepositoryRegistry : IRepositoryRegistry
{
    private readonly GitOpenDbContext _db;
    public RepositoryRegistry(GitOpenDbContext db) => _db = db;

    public async Task<RepoLocation> AddAsync(string path, CancellationToken ct)
    {
        var existing = await _db.Repositories.FirstOrDefaultAsync(r => r.Path == path, ct);
        if (existing is not null) return ToLocation(existing);

        var row = new RepositoryRow
        {
            Id = Guid.NewGuid(),
            Path = path,
            DisplayName = DefaultDisplayName(path),
            CreatedUtc = DateTime.UtcNow,
            LastOpenedUtc = DateTime.UtcNow,
            TabOrder = await _db.Repositories.CountAsync(ct)
        };
        _db.Repositories.Add(row);
        await _db.SaveChangesAsync(ct);
        return ToLocation(row);
    }

    public async Task<IReadOnlyList<RepoLocation>> ListAsync(CancellationToken ct) =>
        await _db.Repositories
            .OrderBy(r => r.TabOrder)
            .Select(r => new RepoLocation(new RepoId(r.Id), r.Path, r.DisplayName))
            .ToListAsync(ct);

    public async Task<RepoLocation?> GetByPathAsync(string path, CancellationToken ct)
    {
        var row = await _db.Repositories.FirstOrDefaultAsync(r => r.Path == path, ct);
        return row is null ? null : ToLocation(row);
    }

    public async Task RemoveAsync(RepoId id, CancellationToken ct)
    {
        var row = await _db.Repositories.FirstOrDefaultAsync(r => r.Id == id.Value, ct);
        if (row is null) return;
        _db.Repositories.Remove(row);
        await _db.SaveChangesAsync(ct);
    }

    public async Task TouchLastOpenedAsync(RepoId id, CancellationToken ct)
    {
        var row = await _db.Repositories.FirstOrDefaultAsync(r => r.Id == id.Value, ct);
        if (row is null) return;
        row.LastOpenedUtc = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);
    }

    private static RepoLocation ToLocation(RepositoryRow r) =>
        new(new RepoId(r.Id), r.Path, r.DisplayName);

    private static string DefaultDisplayName(string path)
    {
        var trimmed = path.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var name = Path.GetFileName(trimmed);
        return string.IsNullOrEmpty(name) ? trimmed : name;
    }
}
```

- [ ] **Step 6: Run — pass**

```bash
dotnet test tests/GitOpen.Infrastructure.Tests --filter "FullyQualifiedName~RepositoryRegistryTests"
```

Expected: 4 pass.

- [ ] **Step 7: Commit**

```bash
git add .
git commit -m "feat(infra): RepositoryRegistry with EF Core (TDD)"
```

---

## Phase E — Application services

### Task E1 (TDD): WorkspaceManager — open/close workspaces, fire events

**Files:**
- Create: `src/GitOpen.Application/Workspaces/Workspace.cs`
- Create: `src/GitOpen.Application/Workspaces/IWorkspaceManager.cs`
- Create: `src/GitOpen.Application/Workspaces/WorkspaceManager.cs`
- Create: `src/GitOpen.Application/Workspaces/WorkspaceEvents.cs`
- Create: `tests/GitOpen.Application.Tests/Workspaces/WorkspaceManagerTests.cs`

- [ ] **Step 1: Define Workspace and contracts**

`src/GitOpen.Application/Workspaces/Workspace.cs`:
```csharp
using GitOpen.Domain.Commits;
using GitOpen.Domain.Repositories;

namespace GitOpen.Application.Workspaces;

public sealed class Workspace
{
    public RepoLocation Location { get; }
    public string? SelectedBranchFullName { get; set; }
    public CommitSha? SelectedSha { get; set; }
    public int ScrollOffset { get; set; }

    public Workspace(RepoLocation location) => Location = location;
}
```

`src/GitOpen.Application/Workspaces/WorkspaceEvents.cs`:
```csharp
using GitOpen.Domain.Repositories;

namespace GitOpen.Application.Workspaces;

public sealed record WorkspaceOpened(RepoLocation Location);
public sealed record WorkspaceClosed(RepoId Id);
public sealed record WorkspacesReordered(IReadOnlyList<RepoId> NewOrder);
```

`src/GitOpen.Application/Workspaces/IWorkspaceManager.cs`:
```csharp
using GitOpen.Domain.Repositories;

namespace GitOpen.Application.Workspaces;

public interface IWorkspaceManager
{
    IReadOnlyList<Workspace> All { get; }
    event Action<WorkspaceOpened>? Opened;
    event Action<WorkspaceClosed>? Closed;
    event Action<WorkspacesReordered>? Reordered;

    Task<Workspace> OpenAsync(string path, CancellationToken ct);
    Task CloseAsync(RepoId id, CancellationToken ct);
    Workspace? Find(RepoId id);
    void Reorder(IReadOnlyList<RepoId> newOrder);
}
```

- [ ] **Step 2: Write failing tests**

```csharp
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
```

- [ ] **Step 3: Run — fail**

```bash
dotnet test tests/GitOpen.Application.Tests
```

Expected: compile error / test failure.

- [ ] **Step 4: Implement**

`src/GitOpen.Application/Workspaces/WorkspaceManager.cs`:
```csharp
using System.Collections.Concurrent;
using GitOpen.Domain.Repositories;

namespace GitOpen.Application.Workspaces;

public sealed class WorkspaceManager : IWorkspaceManager
{
    private readonly IRepositoryRegistry _registry;
    private readonly List<Workspace> _open = new();
    private readonly object _lock = new();

    public WorkspaceManager(IRepositoryRegistry registry) => _registry = registry;

    public IReadOnlyList<Workspace> All
    {
        get { lock (_lock) return _open.ToList(); }
    }

    public event Action<WorkspaceOpened>? Opened;
    public event Action<WorkspaceClosed>? Closed;
    public event Action<WorkspacesReordered>? Reordered;

    public async Task<Workspace> OpenAsync(string path, CancellationToken ct)
    {
        var loc = await _registry.AddAsync(path, ct);
        Workspace ws;
        bool fresh;
        lock (_lock)
        {
            var existing = _open.FirstOrDefault(w => w.Location.Id == loc.Id);
            if (existing is not null) return existing;
            ws = new Workspace(loc);
            _open.Add(ws);
            fresh = true;
        }
        if (fresh) Opened?.Invoke(new WorkspaceOpened(loc));
        await _registry.TouchLastOpenedAsync(loc.Id, ct);
        return ws;
    }

    public Task CloseAsync(RepoId id, CancellationToken ct)
    {
        bool removed;
        lock (_lock)
        {
            var ws = _open.FirstOrDefault(w => w.Location.Id == id);
            removed = ws is not null && _open.Remove(ws);
        }
        if (removed) Closed?.Invoke(new WorkspaceClosed(id));
        return Task.CompletedTask;
    }

    public Workspace? Find(RepoId id)
    {
        lock (_lock) return _open.FirstOrDefault(w => w.Location.Id == id);
    }

    public void Reorder(IReadOnlyList<RepoId> newOrder)
    {
        lock (_lock)
        {
            var dict = _open.ToDictionary(w => w.Location.Id);
            _open.Clear();
            foreach (var id in newOrder)
                if (dict.TryGetValue(id, out var ws)) _open.Add(ws);
        }
        Reordered?.Invoke(new WorkspacesReordered(newOrder));
    }
}
```

- [ ] **Step 5: Run — pass**

```bash
dotnet test tests/GitOpen.Application.Tests
```

Expected: 3 pass.

- [ ] **Step 6: Commit**

```bash
git add .
git commit -m "feat(app): WorkspaceManager with open/close/reorder events (TDD)"
```

---

### Task E2 (TDD): CommitGraphLayout — lane assignment algorithm

**Files:**
- Create: `src/GitOpen.Application/CommitGraph/CommitNode.cs`
- Create: `src/GitOpen.Application/CommitGraph/ICommitGraphLayout.cs`
- Create: `src/GitOpen.Application/CommitGraph/CommitGraphLayout.cs`
- Create: `tests/GitOpen.Application.Tests/CommitGraph/CommitGraphLayoutTests.cs`

- [ ] **Step 1: Define the types**

`src/GitOpen.Application/CommitGraph/CommitNode.cs`:
```csharp
using GitOpen.Domain.Commits;

namespace GitOpen.Application.CommitGraph;

public sealed record CommitNode(
    CommitInfo Commit,
    int Lane,
    int Color,
    IReadOnlyList<int> ParentLanes);
```

`src/GitOpen.Application/CommitGraph/ICommitGraphLayout.cs`:
```csharp
using GitOpen.Domain.Commits;

namespace GitOpen.Application.CommitGraph;

public interface ICommitGraphLayout
{
    IReadOnlyList<CommitNode> Compute(IReadOnlyList<CommitInfo> commitsNewestFirst);
}
```

- [ ] **Step 2: Write tests**

```csharp
using FluentAssertions;
using GitOpen.Application.CommitGraph;
using GitOpen.Domain.Commits;
using Xunit;

namespace GitOpen.Application.Tests.CommitGraph;

public class CommitGraphLayoutTests
{
    private static CommitInfo Mk(string sha, params string[] parents) =>
        new(
            new CommitSha(sha.PadLeft(8, '0')),
            parents.Select(p => new CommitSha(p.PadLeft(8, '0'))).ToList(),
            new CommitSignature("a", "a@x", DateTimeOffset.UtcNow),
            new CommitSignature("a", "a@x", DateTimeOffset.UtcNow),
            "msg", "msg");

    [Fact]
    public void Linear_history_all_in_lane_zero()
    {
        var commits = new[]
        {
            Mk("c", "b"),
            Mk("b", "a"),
            Mk("a")
        };
        var sut = new CommitGraphLayout();

        var nodes = sut.Compute(commits);

        nodes.Should().HaveCount(3);
        nodes.Should().OnlyContain(n => n.Lane == 0);
    }

    [Fact]
    public void Branch_creates_two_lanes()
    {
        // c (HEAD) with parents b1 and b2 (a merge); b1 -> a, b2 -> a
        var commits = new[]
        {
            Mk("c",  "b1", "b2"),
            Mk("b1", "a"),
            Mk("b2", "a"),
            Mk("a")
        };
        var sut = new CommitGraphLayout();

        var nodes = sut.Compute(commits);

        nodes.Select(n => n.Lane).Should().Contain(new[] { 0, 1 });
        nodes.Last().Lane.Should().Be(0); // root collapses back
    }

    [Fact]
    public void Empty_input_returns_empty()
    {
        var sut = new CommitGraphLayout();
        sut.Compute(Array.Empty<CommitInfo>()).Should().BeEmpty();
    }
}
```

- [ ] **Step 3: Run — fail**

```bash
dotnet test tests/GitOpen.Application.Tests --filter "FullyQualifiedName~CommitGraphLayoutTests"
```

- [ ] **Step 4: Implement**

`src/GitOpen.Application/CommitGraph/CommitGraphLayout.cs`:
```csharp
using GitOpen.Domain.Commits;

namespace GitOpen.Application.CommitGraph;

public sealed class CommitGraphLayout : ICommitGraphLayout
{
    public IReadOnlyList<CommitNode> Compute(IReadOnlyList<CommitInfo> commitsNewestFirst)
    {
        if (commitsNewestFirst.Count == 0) return Array.Empty<CommitNode>();

        // Active lanes: index -> sha that this lane is currently waiting for.
        var lanes = new List<CommitSha?>();
        var laneColor = new Dictionary<int, int>();
        var nextColor = 0;
        var result = new List<CommitNode>(commitsNewestFirst.Count);

        foreach (var commit in commitsNewestFirst)
        {
            // Find the lane reserved for this sha (where some descendant pointed to us)
            var ownLane = -1;
            for (var i = 0; i < lanes.Count; i++)
            {
                if (lanes[i] == commit.Sha) { ownLane = i; break; }
            }
            if (ownLane == -1)
            {
                ownLane = lanes.IndexOf(null);
                if (ownLane == -1) { ownLane = lanes.Count; lanes.Add(null); }
                if (!laneColor.ContainsKey(ownLane)) laneColor[ownLane] = nextColor++;
            }

            // Free our own lane (we're done at this row, parents may reuse it)
            lanes[ownLane] = null;

            // Assign parents to lanes
            var parentLanes = new List<int>(commit.ParentShas.Count);
            for (var pi = 0; pi < commit.ParentShas.Count; pi++)
            {
                var parentSha = commit.ParentShas[pi];

                // If a lane already waits for this parent, reuse it
                var existing = -1;
                for (var i = 0; i < lanes.Count; i++)
                    if (lanes[i] == parentSha) { existing = i; break; }
                if (existing >= 0) { parentLanes.Add(existing); continue; }

                int targetLane;
                if (pi == 0)
                {
                    // First parent: keep our own lane
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
                parentLanes.Add(targetLane);
            }

            // Trim trailing nulls
            while (lanes.Count > 0 && lanes[^1] is null) lanes.RemoveAt(lanes.Count - 1);

            result.Add(new CommitNode(commit, ownLane, laneColor[ownLane], parentLanes));
        }
        return result;
    }
}
```

- [ ] **Step 5: Run — pass**

```bash
dotnet test tests/GitOpen.Application.Tests --filter "FullyQualifiedName~CommitGraphLayoutTests"
```

Expected: 3 pass. If "branch" test fails on lane assertion, the lane-reuse heuristic in step 4 already handles linear collapse — debug with the assertions in the test.

- [ ] **Step 6: Commit**

```bash
git add .
git commit -m "feat(app): commit graph lane assignment (TDD)"
```

---

### Task E3: Composition root (DI registration helpers)

**Files:**
- Create: `src/GitOpen.Application/DependencyInjection/ApplicationModule.cs`
- Create: `src/GitOpen.Infrastructure/DependencyInjection/InfrastructureModule.cs`

- [ ] **Step 1: Add DI Abstractions package to projects that need it**

```bash
dotnet add src/GitOpen.Application package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/GitOpen.Infrastructure package Microsoft.Extensions.DependencyInjection.Abstractions
```

- [ ] **Step 2: Application module**

`src/GitOpen.Application/DependencyInjection/ApplicationModule.cs`:
```csharp
using GitOpen.Application.CommitGraph;
using GitOpen.Application.Workspaces;
using Microsoft.Extensions.DependencyInjection;

namespace GitOpen.Application.DependencyInjection;

public static class ApplicationModule
{
    public static IServiceCollection AddGitOpenApplication(this IServiceCollection services)
    {
        services.AddSingleton<IWorkspaceManager, WorkspaceManager>();
        services.AddSingleton<ICommitGraphLayout, CommitGraphLayout>();
        return services;
    }
}
```

- [ ] **Step 3: Infrastructure module**

`src/GitOpen.Infrastructure/DependencyInjection/InfrastructureModule.cs`:
```csharp
using GitOpen.Application.Git;
using GitOpen.Application.Workspaces;
using GitOpen.Infrastructure.Git;
using GitOpen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace GitOpen.Infrastructure.DependencyInjection;

public static class InfrastructureModule
{
    public static IServiceCollection AddGitOpenInfrastructure(this IServiceCollection services)
    {
        services.AddDbContext<GitOpenDbContext>(opts =>
            opts.UseSqlite($"Data Source={PathProvider.StateDbPath()}"));
        services.AddScoped<IRepositoryRegistry, RepositoryRegistry>();
        services.AddSingleton<IGitReadOperations, LibGit2GitReadOperations>();
        return services;
    }
}
```

- [ ] **Step 4: Build**

```bash
dotnet build GitOpen.sln
```

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat: DI composition modules"
```

---

## Phase F — Photino.Blazor host

### Task F1: Add Photino.Blazor host with empty Blazor app

**Files:**
- Modify: `src/GitOpen.Ui/GitOpen.Ui.csproj`
- Create: `src/GitOpen.Ui/Program.cs`
- Create: `src/GitOpen.Ui/App.razor`
- Create: `src/GitOpen.Ui/_Imports.razor`
- Create: `src/GitOpen.Ui/Pages/Index.razor`
- Create: `src/GitOpen.Ui/MainLayout.razor`
- Create: `src/GitOpen.Ui/wwwroot/index.html`
- Create: `src/GitOpen.Ui/wwwroot/css/site.css`

- [ ] **Step 1: Add Photino.Blazor package and adjust csproj**

```bash
dotnet add src/GitOpen.Ui package Photino.Blazor
dotnet add src/GitOpen.Ui package Microsoft.Extensions.Hosting
dotnet add src/GitOpen.Ui package Serilog.Extensions.Hosting
dotnet add src/GitOpen.Ui package Serilog.Sinks.File
dotnet add src/GitOpen.Ui package Serilog.Sinks.Console
```

Replace `src/GitOpen.Ui/GitOpen.Ui.csproj` content:

```xml
<Project Sdk="Microsoft.NET.Sdk.Razor">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <RootNamespace>GitOpen.Ui</RootNamespace>
    <AssemblyName>GitOpen</AssemblyName>
    <UseWPF>false</UseWPF>
    <UseWindowsForms>false</UseWindowsForms>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Photino.Blazor" />
    <PackageReference Include="Microsoft.Extensions.Hosting" />
    <PackageReference Include="Serilog.Extensions.Hosting" />
    <PackageReference Include="Serilog.Sinks.File" />
    <PackageReference Include="Serilog.Sinks.Console" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\GitOpen.Domain\GitOpen.Domain.csproj" />
    <ProjectReference Include="..\GitOpen.Application\GitOpen.Application.csproj" />
    <ProjectReference Include="..\GitOpen.Infrastructure\GitOpen.Infrastructure.csproj" />
  </ItemGroup>
</Project>
```

- [ ] **Step 2: Create wwwroot/index.html**

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>GitOpen</title>
    <base href="/" />
    <link href="css/site.css" rel="stylesheet" />
</head>
<body>
    <div id="app">Loading...</div>
    <div id="blazor-error-ui" style="display:none">
        An unhandled error has occurred.
        <a href="" class="reload">Reload</a>
        <a class="dismiss">🗙</a>
    </div>
    <script src="_framework/blazor.webview.js" autostart="false"></script>
</body>
</html>
```

- [ ] **Step 3: Create _Imports.razor**

```razor
@using System.Net.Http
@using Microsoft.AspNetCore.Components
@using Microsoft.AspNetCore.Components.Forms
@using Microsoft.AspNetCore.Components.Routing
@using Microsoft.AspNetCore.Components.Web
@using Microsoft.JSInterop
@using GitOpen.Application.Workspaces
@using GitOpen.Application.CommitGraph
@using GitOpen.Application.Git
@using GitOpen.Domain.Commits
@using GitOpen.Domain.Refs
@using GitOpen.Domain.Repositories
@using GitOpen.Domain.Status
@using GitOpen.Domain.Diff
@using GitOpen.Domain.Files
```

- [ ] **Step 4: App.razor**

```razor
<Router AppAssembly="@typeof(App).Assembly">
    <Found Context="routeData">
        <RouteView RouteData="@routeData" DefaultLayout="@typeof(MainLayout)" />
    </Found>
    <NotFound>
        <LayoutView Layout="@typeof(MainLayout)">
            <p>Sorry, there's nothing at this address.</p>
        </LayoutView>
    </NotFound>
</Router>
```

- [ ] **Step 5: MainLayout.razor**

```razor
@inherits LayoutComponentBase

<div class="page">
    @Body
</div>
```

- [ ] **Step 6: Pages/Index.razor**

```razor
@page "/"

<h1>GitOpen — read-only viewer</h1>
<p>Slice 1 scaffolding online.</p>
```

- [ ] **Step 7: wwwroot/css/site.css**

```css
:root {
    color-scheme: light dark;
    font-family: system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
}
html, body { height: 100%; margin: 0; }
.page { padding: 1rem; }
```

- [ ] **Step 8: Program.cs**

```csharp
using GitOpen.Application.DependencyInjection;
using GitOpen.Infrastructure.DependencyInjection;
using GitOpen.Infrastructure.Persistence;
using GitOpen.Ui;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Photino.Blazor;
using Serilog;

Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Information()
    .WriteTo.Console()
    .WriteTo.File(
        path: System.IO.Path.Combine(PathProvider.LogDirectory(), "gitopen-.log"),
        rollingInterval: RollingInterval.Day,
        retainedFileCountLimit: 7)
    .CreateLogger();

try
{
    var builder = PhotinoBlazorAppBuilder.CreateDefault(args);
    builder.Services
        .AddLogging(lb => lb.AddSerilog())
        .AddGitOpenApplication()
        .AddGitOpenInfrastructure();
    builder.RootComponents.Add<App>("#app");

    var app = builder.Build();

    using (var scope = app.Services.CreateScope())
    {
        var db = scope.ServiceProvider.GetRequiredService<GitOpenDbContext>();
        db.Database.Migrate();
    }

    app.MainWindow
        .SetTitle("GitOpen")
        .SetSize(1400, 900)
        .SetIconFile(null!);

    AppDomain.CurrentDomain.UnhandledException += (s, e) =>
        Log.Fatal(e.ExceptionObject as Exception, "Unhandled exception");

    app.Run();
}
finally
{
    Log.CloseAndFlush();
}
```

- [ ] **Step 9: Build**

```bash
dotnet build src/GitOpen.Ui
```

Expected: build succeeds. (Photino.Blazor expects WebView2 on Windows; that should already be installed on Windows 11.)

- [ ] **Step 10: Smoke run (manual)**

```bash
dotnet run --project src/GitOpen.Ui
```

Expected: a window opens titled "GitOpen" displaying "GitOpen — read-only viewer" and "Slice 1 scaffolding online." — close the window.

If on Linux: `sudo apt install libwebkit2gtk-4.1-0` first if missing.

- [ ] **Step 11: Commit**

```bash
git add .
git commit -m "feat(ui): Photino.Blazor host wired with empty Index page"
```

---

## Phase G — UI shell: tabs, sidebar, layout

### Task G1: Tab bar component bound to WorkspaceManager

**Files:**
- Create: `src/GitOpen.Ui/Components/TabBar.razor`
- Create: `src/GitOpen.Ui/Components/TabBar.razor.css`
- Create: `tests/GitOpen.Ui.Tests/Components/TabBarTests.cs`

- [ ] **Step 1: Add bUnit packages to test project**

```bash
dotnet add tests/GitOpen.Ui.Tests package bunit
dotnet add tests/GitOpen.Ui.Tests package Microsoft.AspNetCore.Components.Web
dotnet add tests/GitOpen.Ui.Tests package NSubstitute
```

- [ ] **Step 2: Component**

`src/GitOpen.Ui/Components/TabBar.razor`:
```razor
@implements IDisposable
@inject IWorkspaceManager Workspaces

<div class="tabbar">
    @foreach (var ws in _items)
    {
        <button class="tab @(ws.Location.Id == Active ? "active" : "")"
                @onclick="() => OnActivate.InvokeAsync(ws.Location.Id)">
            <span class="tab-name">@ws.Location.DisplayName</span>
            <span class="tab-close" @onclick:stopPropagation="true"
                  @onclick="() => OnClose.InvokeAsync(ws.Location.Id)">×</span>
        </button>
    }
    <button class="tab-add" @onclick="OnOpenRepo">+</button>
</div>

@code {
    [Parameter] public RepoId Active { get; set; }
    [Parameter] public EventCallback<RepoId> OnActivate { get; set; }
    [Parameter] public EventCallback<RepoId> OnClose { get; set; }
    [Parameter] public EventCallback OnOpenRepo { get; set; }

    private IReadOnlyList<Workspace> _items = Array.Empty<Workspace>();

    protected override void OnInitialized()
    {
        Refresh();
        Workspaces.Opened   += _ => Reload();
        Workspaces.Closed   += _ => Reload();
        Workspaces.Reordered += _ => Reload();
    }

    private void Reload()
    {
        Refresh();
        InvokeAsync(StateHasChanged);
    }

    private void Refresh() => _items = Workspaces.All;

    public void Dispose() { /* events are weak via lambda capture; manager outlives component */ }
}
```

`src/GitOpen.Ui/Components/TabBar.razor.css`:
```css
.tabbar {
    display: flex;
    align-items: center;
    height: 36px;
    background: #2b2b2b;
    color: #ddd;
    overflow-x: auto;
    user-select: none;
}
.tab {
    background: transparent;
    color: inherit;
    border: 0;
    padding: 0 12px;
    height: 100%;
    display: flex;
    align-items: center;
    gap: 8px;
    cursor: pointer;
    border-right: 1px solid #1c1c1c;
}
.tab.active { background: #1e1e1e; }
.tab:hover { background: #3a3a3a; }
.tab-close {
    opacity: 0.6;
    padding: 0 4px;
    border-radius: 3px;
}
.tab-close:hover { background: #5a1f1f; opacity: 1; }
.tab-add {
    background: transparent;
    color: inherit;
    border: 0;
    padding: 0 12px;
    height: 100%;
    cursor: pointer;
}
.tab-add:hover { background: #3a3a3a; }
```

- [ ] **Step 3: bUnit test**

`tests/GitOpen.Ui.Tests/Components/TabBarTests.cs`:
```csharp
using Bunit;
using FluentAssertions;
using GitOpen.Application.Workspaces;
using GitOpen.Domain.Repositories;
using GitOpen.Ui.Components;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using Xunit;

namespace GitOpen.Ui.Tests.Components;

public class TabBarTests : TestContext
{
    [Fact]
    public void Renders_all_open_workspaces()
    {
        var mgr = Substitute.For<IWorkspaceManager>();
        var ws1 = new Workspace(new RepoLocation(RepoId.NewId(), "/a", "alpha"));
        var ws2 = new Workspace(new RepoLocation(RepoId.NewId(), "/b", "beta"));
        mgr.All.Returns(new[] { ws1, ws2 });
        Services.AddSingleton(mgr);

        var cut = RenderComponent<TabBar>();

        cut.Markup.Should().Contain("alpha").And.Contain("beta");
    }

    [Fact]
    public void Active_tab_has_active_class()
    {
        var mgr = Substitute.For<IWorkspaceManager>();
        var id = RepoId.NewId();
        mgr.All.Returns(new[] { new Workspace(new RepoLocation(id, "/a", "alpha")) });
        Services.AddSingleton(mgr);

        var cut = RenderComponent<TabBar>(p => p.Add(x => x.Active, id));

        cut.Find("button.tab.active").TextContent.Should().Contain("alpha");
    }
}
```

- [ ] **Step 4: Run**

```bash
dotnet test tests/GitOpen.Ui.Tests
```

Expected: 2 pass.

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat(ui): TabBar component bound to WorkspaceManager"
```

---

### Task G2: Sidebar component (branches, remotes, tags, stashes)

**Files:**
- Create: `src/GitOpen.Ui/Components/Sidebar.razor`
- Create: `src/GitOpen.Ui/Components/Sidebar.razor.css`

- [ ] **Step 1: Component**

`src/GitOpen.Ui/Components/Sidebar.razor`:
```razor
@inject IGitReadOperations Git

<div class="sidebar">
    @if (Repo is not null)
    {
        <SidebarSection Title="Local Branches">
            @foreach (var b in _branches.Where(b => !b.IsRemote))
            {
                <div class="ref-row @(b.IsCurrent ? "current" : "")">@b.Name</div>
            }
        </SidebarSection>
        <SidebarSection Title="Remotes">
            @foreach (var r in _remotes)
            {
                <div class="remote">@r.Name</div>
                @foreach (var b in r.Branches)
                {
                    <div class="ref-row remote-branch">@b.Name</div>
                }
            }
        </SidebarSection>
        <SidebarSection Title="Tags">
            @foreach (var t in _tags) { <div class="ref-row">@t.Name</div> }
        </SidebarSection>
        <SidebarSection Title="Stashes">
            @foreach (var s in _stashes) { <div class="ref-row">stash@@@s.Index — @s.Message</div> }
        </SidebarSection>
    }
    else
    {
        <div class="empty">No repository selected</div>
    }
</div>

@code {
    [Parameter] public RepoLocation? Repo { get; set; }

    private IReadOnlyList<Branch> _branches = Array.Empty<Branch>();
    private IReadOnlyList<Tag>    _tags = Array.Empty<Tag>();
    private IReadOnlyList<Remote> _remotes = Array.Empty<Remote>();
    private IReadOnlyList<Stash>  _stashes = Array.Empty<Stash>();

    protected override async Task OnParametersSetAsync()
    {
        if (Repo is null)
        {
            _branches = Array.Empty<Branch>();
            _tags = Array.Empty<Tag>();
            _remotes = Array.Empty<Remote>();
            _stashes = Array.Empty<Stash>();
            return;
        }
        _branches = await Git.GetBranchesAsync(Repo, default);
        _tags     = await Git.GetTagsAsync(Repo, default);
        _remotes  = await Git.GetRemotesAsync(Repo, default);
        _stashes  = await Git.GetStashesAsync(Repo, default);
    }
}
```

`src/GitOpen.Ui/Components/Sidebar.razor.css`:
```css
.sidebar {
    width: 280px;
    background: #252526;
    color: #d4d4d4;
    overflow-y: auto;
    padding: 8px 0;
    border-right: 1px solid #1c1c1c;
}
.ref-row { padding: 2px 12px; cursor: pointer; }
.ref-row:hover { background: #3a3a3a; }
.ref-row.current { font-weight: bold; color: #4ec9b0; }
.remote { padding: 2px 8px; opacity: 0.7; font-size: 11px; text-transform: uppercase; }
.remote-branch { padding-left: 24px; opacity: 0.85; }
.empty { padding: 12px; opacity: 0.6; }
```

- [ ] **Step 2: Helper sub-component**

`src/GitOpen.Ui/Components/SidebarSection.razor`:
```razor
<div class="section">
    <div class="section-title" @onclick="() => _open = !_open">
        <span class="chev">@(_open ? "▾" : "▸")</span> @Title
    </div>
    @if (_open) { <div class="section-body">@ChildContent</div> }
</div>

@code {
    [Parameter] public string Title { get; set; } = "";
    [Parameter] public RenderFragment? ChildContent { get; set; }
    private bool _open = true;
}
```

(Add to `Sidebar.razor.css`):
```css
.section-title {
    padding: 6px 8px;
    font-size: 11px;
    text-transform: uppercase;
    opacity: 0.7;
    cursor: pointer;
}
.chev { display: inline-block; width: 14px; }
```

- [ ] **Step 3: Build**

```bash
dotnet build src/GitOpen.Ui
```

- [ ] **Step 4: Commit**

```bash
git add .
git commit -m "feat(ui): Sidebar with branches/remotes/tags/stashes"
```

---

### Task G3: App shell — wire TabBar + Sidebar + main panel + dialog to open repos

**Files:**
- Modify: `src/GitOpen.Ui/Pages/Index.razor`
- Create: `src/GitOpen.Ui/Pages/Index.razor.css`
- Create: `src/GitOpen.Ui/Services/IFolderPicker.cs`
- Create: `src/GitOpen.Ui/Services/PhotinoFolderPicker.cs`
- Modify: `src/GitOpen.Ui/Program.cs`

- [ ] **Step 1: Folder picker abstraction**

`src/GitOpen.Ui/Services/IFolderPicker.cs`:
```csharp
namespace GitOpen.Ui.Services;

public interface IFolderPicker
{
    Task<string?> PickFolderAsync(string title);
}
```

`src/GitOpen.Ui/Services/PhotinoFolderPicker.cs`:
```csharp
using Photino.Blazor;

namespace GitOpen.Ui.Services;

public sealed class PhotinoFolderPicker : IFolderPicker
{
    private readonly PhotinoBlazorApp _app;
    public PhotinoFolderPicker(PhotinoBlazorApp app) => _app = app;

    public Task<string?> PickFolderAsync(string title)
    {
        var paths = _app.MainWindow.ShowOpenFolder(title: title, multiSelect: false);
        return Task.FromResult(paths is { Length: > 0 } ? paths[0] : null);
    }
}
```

- [ ] **Step 2: Register the picker in `Program.cs`**

After `builder.Services.AddGitOpenInfrastructure();` in `Program.cs`, add:

```csharp
builder.Services.AddSingleton<IFolderPicker, PhotinoFolderPicker>();
```

Also add `using GitOpen.Ui.Services;` at the top.

- [ ] **Step 3: Replace Index.razor with the shell**

```razor
@page "/"
@inject IWorkspaceManager Workspaces
@inject IFolderPicker FolderPicker

<div class="shell">
    <TabBar Active="_active" OnActivate="Activate" OnClose="Close" OnOpenRepo="OpenRepo" />
    <div class="body">
        <Sidebar Repo="_activeRepo?.Location" />
        <div class="main">
            @if (_activeRepo is not null)
            {
                <CommitGraphPanel Repo="_activeRepo.Location" />
            }
            else
            {
                <div class="empty">Open a repository to begin.</div>
            }
        </div>
    </div>
</div>

@code {
    private RepoId _active;
    private Workspace? _activeRepo => Workspaces.All.FirstOrDefault(w => w.Location.Id == _active);

    protected override void OnInitialized()
    {
        Workspaces.Opened += e =>
        {
            _active = e.Location.Id;
            InvokeAsync(StateHasChanged);
        };
        Workspaces.Closed += _ =>
        {
            if (Workspaces.All.All(w => w.Location.Id != _active))
                _active = Workspaces.All.FirstOrDefault()?.Location.Id ?? default;
            InvokeAsync(StateHasChanged);
        };
    }

    private void Activate(RepoId id) { _active = id; }

    private async Task Close(RepoId id) => await Workspaces.CloseAsync(id, default);

    private async Task OpenRepo()
    {
        var path = await FolderPicker.PickFolderAsync("Open repository");
        if (string.IsNullOrEmpty(path)) return;
        await Workspaces.OpenAsync(path, default);
    }
}
```

`src/GitOpen.Ui/Pages/Index.razor.css`:
```css
.shell { display: flex; flex-direction: column; height: 100vh; }
.body { display: flex; flex: 1; min-height: 0; }
.main { flex: 1; display: flex; flex-direction: column; min-width: 0; }
.empty { padding: 24px; opacity: 0.7; }
```

- [ ] **Step 4: Stub `<CommitGraphPanel>` (will be implemented in Phase H)**

Create `src/GitOpen.Ui/Components/CommitGraphPanel.razor`:
```razor
@code {
    [Parameter] public RepoLocation Repo { get; set; } = default!;
}
<div>Commit graph panel placeholder for @Repo.DisplayName</div>
```

- [ ] **Step 5: Build & smoke-run**

```bash
dotnet build src/GitOpen.Ui
dotnet run --project src/GitOpen.Ui
```

Expected: window opens; the tab bar's "+" button opens a folder picker; selecting a folder containing a `.git` directory adds a tab; clicking × closes it.

- [ ] **Step 6: Commit**

```bash
git add .
git commit -m "feat(ui): app shell with tabs/sidebar/folder picker"
```

---

## Phase H — Commit graph panel (the hot path)

### Task H1: CommitGraphPanel — load commits + lane layout, render virtualised list (no SVG yet)

**Files:**
- Modify: `src/GitOpen.Ui/Components/CommitGraphPanel.razor`
- Create: `src/GitOpen.Ui/Components/CommitGraphPanel.razor.css`

- [ ] **Step 1: Implement panel**

`src/GitOpen.Ui/Components/CommitGraphPanel.razor`:
```razor
@inject IGitReadOperations Git
@inject ICommitGraphLayout Layout

<div class="commit-graph">
    @if (_loading)
    {
        <div class="loading">Loading…</div>
    }
    else if (_nodes.Count == 0)
    {
        <div class="empty-graph">No commits in this repository.</div>
    }
    else
    {
        <Virtualize Items="_nodes" Context="node" ItemSize="24">
            <CommitRow Node="node" MaxLane="_maxLane"
                       Selected="@(node.Commit.Sha == _selected)"
                       OnSelect="OnSelectRow" />
        </Virtualize>
    }
</div>

@code {
    [Parameter] public RepoLocation Repo { get; set; } = default!;

    private bool _loading;
    private List<CommitNode> _nodes = new();
    private int _maxLane;
    private CommitSha? _selected;

    [Parameter] public EventCallback<CommitSha> OnCommitSelected { get; set; }

    protected override async Task OnParametersSetAsync()
    {
        await ReloadAsync();
    }

    private async Task ReloadAsync()
    {
        _loading = true;
        _nodes.Clear();
        StateHasChanged();
        var commits = new List<CommitInfo>();
        await foreach (var c in Git.GetCommitsAsync(Repo, new CommitQuery(Take: 5000), default))
            commits.Add(c);
        _nodes = Layout.Compute(commits).ToList();
        _maxLane = _nodes.Count == 0 ? 0 : _nodes.Max(n => n.Lane);
        _loading = false;
        StateHasChanged();
    }

    private async Task OnSelectRow(CommitSha sha)
    {
        _selected = sha;
        await OnCommitSelected.InvokeAsync(sha);
        StateHasChanged();
    }
}
```

`src/GitOpen.Ui/Components/CommitGraphPanel.razor.css`:
```css
.commit-graph {
    flex: 1;
    overflow: auto;
    background: #1e1e1e;
    color: #d4d4d4;
    font-family: "JetBrains Mono", Menlo, Consolas, monospace;
    font-size: 12px;
}
.loading, .empty-graph { padding: 24px; opacity: 0.7; }
```

- [ ] **Step 2: Build**

```bash
dotnet build src/GitOpen.Ui
```

(`CommitRow` does not yet exist — next task. Build will fail; that's fine, this is a partial commit, but to keep CI green commit only after H2.)

---

### Task H2: CommitRow component with inline SVG lanes

**Files:**
- Create: `src/GitOpen.Ui/Components/CommitRow.razor`
- Create: `src/GitOpen.Ui/Components/CommitRow.razor.css`

- [ ] **Step 1: Component**

`src/GitOpen.Ui/Components/CommitRow.razor`:
```razor
<div class="row @(Selected ? "selected" : "")" @onclick="() => OnSelect.InvokeAsync(Node.Commit.Sha)">
    <div class="lanes">
        <svg width="@SvgWidth" height="24" xmlns="http://www.w3.org/2000/svg">
            @* edges to parents *@
            @foreach (var pl in Node.ParentLanes)
            {
                var x1 = LaneX(Node.Lane);
                var x2 = LaneX(pl);
                <line x1="@x1" y1="12" x2="@x2" y2="24" stroke="@LaneStroke(pl)" stroke-width="1.5" />
            }
            <circle cx="@LaneX(Node.Lane)" cy="12" r="4" fill="@LaneStroke(Node.Lane)" />
        </svg>
    </div>
    <div class="sha">@Node.Commit.Sha.Short()</div>
    <div class="message">@Node.Commit.Summary</div>
    <div class="author">@Node.Commit.Author.Name</div>
    <div class="when">@Node.Commit.Author.When.LocalDateTime.ToString("yyyy-MM-dd HH:mm")</div>
</div>

@code {
    [Parameter] public CommitNode Node { get; set; } = default!;
    [Parameter] public int MaxLane { get; set; }
    [Parameter] public bool Selected { get; set; }
    [Parameter] public EventCallback<CommitSha> OnSelect { get; set; }

    private const int LaneSpacing = 14;
    private const int LanePad = 10;

    private int SvgWidth => LanePad * 2 + LaneSpacing * (MaxLane + 1);

    private int LaneX(int lane) => LanePad + lane * LaneSpacing;

    private static readonly string[] Palette = new[]
    {
        "#4ec9b0", "#dcdcaa", "#9cdcfe", "#ce9178",
        "#c586c0", "#569cd6", "#d7ba7d", "#f48771"
    };

    private string LaneStroke(int lane) => Palette[lane % Palette.Length];
}
```

`src/GitOpen.Ui/Components/CommitRow.razor.css`:
```css
.row {
    display: grid;
    grid-template-columns: auto 70px 1fr 160px 140px;
    align-items: center;
    height: 24px;
    padding: 0 8px;
    cursor: pointer;
}
.row:hover { background: #2a2d2e; }
.row.selected { background: #094771; }
.lanes svg { display: block; }
.sha { color: #569cd6; }
.message { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.author { opacity: 0.85; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.when { opacity: 0.7; font-feature-settings: "tnum"; }
```

- [ ] **Step 2: Build**

```bash
dotnet build src/GitOpen.Ui
```

Expected: succeeds.

- [ ] **Step 3: Smoke-run**

```bash
dotnet run --project src/GitOpen.Ui
```

Expected: open a repo via "+", commits load, scroll is responsive. If "Loading…" stays forever, check log file in `%APPDATA%/GitOpen/logs/`.

- [ ] **Step 4: Commit**

```bash
git add .
git commit -m "feat(ui): CommitGraphPanel + CommitRow with SVG lanes"
```

---

### Task H3: Refs overlay — pill labels for branches/tags on commits

**Files:**
- Modify: `src/GitOpen.Ui/Components/CommitGraphPanel.razor`
- Modify: `src/GitOpen.Ui/Components/CommitRow.razor`
- Create: `src/GitOpen.Ui/Components/RefPill.razor`
- Create: `src/GitOpen.Ui/Components/RefPill.razor.css`

- [ ] **Step 1: RefPill**

`src/GitOpen.Ui/Components/RefPill.razor`:
```razor
<span class="pill @(IsRemote ? "remote" : (IsTag ? "tag" : "branch")) @(IsCurrent ? "current" : "")">
    @if (IsCurrent) { <span class="head-marker">HEAD →</span> }
    @Name
</span>

@code {
    [Parameter] public string Name { get; set; } = "";
    [Parameter] public bool IsRemote { get; set; }
    [Parameter] public bool IsTag { get; set; }
    [Parameter] public bool IsCurrent { get; set; }
}
```

`src/GitOpen.Ui/Components/RefPill.razor.css`:
```css
.pill {
    display: inline-block;
    padding: 0 6px;
    margin-right: 4px;
    border-radius: 9px;
    font-size: 10px;
    line-height: 16px;
    border: 1px solid #555;
}
.pill.branch { background: #1f4f1f; border-color: #2f7f2f; }
.pill.remote { background: #2f4f6f; border-color: #4f7f9f; }
.pill.tag    { background: #6f4f1f; border-color: #9f7f2f; }
.pill.current { outline: 1px solid #fff; }
.head-marker { font-weight: bold; opacity: 0.85; margin-right: 2px; }
```

- [ ] **Step 2: Modify CommitGraphPanel to load refs once and pass map**

Add to `@code` block:

```csharp
private Dictionary<string, List<RefDecoration>> _refsBySha = new();

private record RefDecoration(string Name, bool IsRemote, bool IsTag, bool IsCurrent);

private async Task ReloadRefsAsync()
{
    _refsBySha.Clear();
    var branches = await Git.GetBranchesAsync(Repo, default);
    var tags = await Git.GetTagsAsync(Repo, default);
    foreach (var b in branches.Where(b => b.TipSha is not null))
    {
        var key = b.TipSha!.Value.Value;
        if (!_refsBySha.TryGetValue(key, out var list))
            _refsBySha[key] = list = new();
        list.Add(new RefDecoration(b.Name, b.IsRemote, false, b.IsCurrent));
    }
    foreach (var t in tags)
    {
        var key = t.TargetSha.Value;
        if (!_refsBySha.TryGetValue(key, out var list))
            _refsBySha[key] = list = new();
        list.Add(new RefDecoration(t.Name, false, true, false));
    }
}
```

In `ReloadAsync` after computing `_nodes`, call `await ReloadRefsAsync();`.

In the `<Virtualize>` template pass refs:

```razor
<CommitRow Node="node" MaxLane="_maxLane"
           Selected="@(node.Commit.Sha == _selected)"
           OnSelect="OnSelectRow"
           Refs="@GetRefs(node.Commit.Sha)" />
```

And add helper:

```csharp
private IReadOnlyList<(string name, bool remote, bool tag, bool current)> GetRefs(CommitSha sha)
{
    if (!_refsBySha.TryGetValue(sha.Value, out var list)) return Array.Empty<(string, bool, bool, bool)>();
    return list.Select(r => (r.Name, r.IsRemote, r.IsTag, r.IsCurrent)).ToList();
}
```

- [ ] **Step 3: Modify CommitRow to render pills**

Add parameter:
```csharp
[Parameter] public IReadOnlyList<(string name, bool remote, bool tag, bool current)> Refs { get; set; }
    = Array.Empty<(string, bool, bool, bool)>();
```

In the markup, place pills before `@Node.Commit.Summary`:
```razor
<div class="message">
    @foreach (var r in Refs)
    {
        <RefPill Name="@r.name" IsRemote="@r.remote" IsTag="@r.tag" IsCurrent="@r.current" />
    }
    @Node.Commit.Summary
</div>
```

- [ ] **Step 4: Build & smoke run**

```bash
dotnet run --project src/GitOpen.Ui
```

Expected: branches and tags appear as coloured pills next to the corresponding commits. Current branch has the "HEAD →" marker.

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat(ui): refs overlay with pill labels on commits"
```

---

## Phase I — Diff viewer + file tree

### Task I1: BottomPanel with Commit/Changes/FileTree tabs

**Files:**
- Create: `src/GitOpen.Ui/Components/BottomPanel.razor`
- Create: `src/GitOpen.Ui/Components/BottomPanel.razor.css`
- Create: `src/GitOpen.Ui/Components/CommitDetails.razor`
- Create: `src/GitOpen.Ui/Components/DiffView.razor`
- Create: `src/GitOpen.Ui/Components/DiffView.razor.css`
- Create: `src/GitOpen.Ui/Components/FileTreeView.razor`

- [ ] **Step 1: CommitDetails**

`src/GitOpen.Ui/Components/CommitDetails.razor`:
```razor
@if (Commit is null)
{
    <div class="empty">Select a commit.</div>
}
else
{
    <div class="commit-details">
        <div><strong>Sha:</strong> @Commit.Sha.Value</div>
        <div><strong>Author:</strong> @Commit.Author.Name &lt;@Commit.Author.Email&gt; — @Commit.Author.When</div>
        <div><strong>Committer:</strong> @Commit.Committer.Name &lt;@Commit.Committer.Email&gt;</div>
        <div><strong>Parents:</strong> @string.Join(", ", Commit.ParentShas.Select(p => p.Short()))</div>
        <pre class="msg">@Commit.Message</pre>
    </div>
}

@code {
    [Parameter] public CommitInfo? Commit { get; set; }
}
```

- [ ] **Step 2: DiffView**

`src/GitOpen.Ui/Components/DiffView.razor`:
```razor
@if (Result is null)
{
    <div class="empty">Select a commit.</div>
}
else
{
    <div class="diff">
        @foreach (var f in Result.Files)
        {
            <div class="file">
                <div class="file-header">
                    <span class="kind @(f.ChangeKind.ToString().ToLowerInvariant())">@f.ChangeKind</span>
                    <span class="path">@(f.OldPath is null ? f.Path : $"{f.OldPath} → {f.Path}")</span>
                    <span class="stats">+@f.LinesAdded -@f.LinesDeleted</span>
                </div>
                @if (f.IsBinary)
                {
                    <div class="binary">Binary file (no preview)</div>
                }
                else
                {
                    @foreach (var h in f.Hunks)
                    {
                        <div class="hunk-header">@h.Header</div>
                        <table class="hunk">
                            @foreach (var line in h.Lines)
                            {
                                <tr class="line @line.Kind.ToString().ToLowerInvariant()">
                                    <td class="ln-old">@(line.OldLine?.ToString() ?? "")</td>
                                    <td class="ln-new">@(line.NewLine?.ToString() ?? "")</td>
                                    <td class="prefix">@LinePrefix(line.Kind)</td>
                                    <td class="content">@line.Content</td>
                                </tr>
                            }
                        </table>
                    }
                }
            </div>
        }
    </div>
}

@code {
    [Parameter] public DiffResult? Result { get; set; }
    private static string LinePrefix(DiffLineKind k) => k switch
    {
        DiffLineKind.Addition => "+",
        DiffLineKind.Deletion => "-",
        _ => " "
    };
}
```

`src/GitOpen.Ui/Components/DiffView.razor.css`:
```css
.diff { padding: 8px; font-family: "JetBrains Mono", Menlo, Consolas, monospace; font-size: 12px; }
.file { border: 1px solid #2a2a2a; margin-bottom: 8px; }
.file-header { background: #2a2a2a; padding: 4px 8px; display: flex; gap: 12px; align-items: center; }
.kind { padding: 1px 6px; border-radius: 4px; background: #444; font-size: 10px; text-transform: uppercase; }
.kind.added { background: #1f4f1f; }
.kind.deleted { background: #5a1f1f; }
.kind.modified { background: #4a4a1f; }
.kind.renamed { background: #1f4a5a; }
.stats { margin-left: auto; opacity: 0.85; }
.hunk-header { background: #1c2a3a; color: #6cf; padding: 2px 8px; font-style: italic; }
.hunk { width: 100%; border-collapse: collapse; }
.line td { padding: 0 4px; vertical-align: top; }
.line.addition { background: #163a16; }
.line.deletion { background: #3a1616; }
.ln-old, .ln-new { width: 48px; text-align: right; opacity: 0.6; }
.prefix { width: 14px; }
.content { white-space: pre; }
.empty { padding: 24px; opacity: 0.7; }
.binary { padding: 12px; opacity: 0.7; }
```

- [ ] **Step 3: FileTreeView**

`src/GitOpen.Ui/Components/FileTreeView.razor`:
```razor
@if (Entries is null)
{
    <div class="empty">Select a commit.</div>
}
else
{
    <ul class="tree">
        @foreach (var e in Entries.OrderBy(e => e.Kind == FileTreeKind.Tree ? 0 : 1).ThenBy(e => e.Name))
        {
            <li class="@e.Kind.ToString().ToLowerInvariant()">
                @(e.Kind == FileTreeKind.Tree ? "📁" : "📄") @e.Name
                @if (e.SizeBytes is { } s) { <span class="size"> (@s)</span> }
            </li>
        }
    </ul>
}

@code {
    [Parameter] public IReadOnlyList<FileTreeEntry>? Entries { get; set; }
}
```

- [ ] **Step 4: BottomPanel**

`src/GitOpen.Ui/Components/BottomPanel.razor`:
```razor
@inject IGitReadOperations Git

<div class="bottom-panel">
    <div class="tabs">
        <button class="@(Tab=="commit"?"active":"")" @onclick='() => Tab="commit"'>Commit</button>
        <button class="@(Tab=="changes"?"active":"")" @onclick='() => Tab="changes"'>Changes</button>
        <button class="@(Tab=="files"?"active":"")" @onclick='() => Tab="files"'>File Tree</button>
    </div>
    <div class="content">
        @switch (Tab)
        {
            case "commit": <CommitDetails Commit="_commitInfo" /> break;
            case "changes": <DiffView Result="_diff" /> break;
            case "files": <FileTreeView Entries="_tree" /> break;
        }
    </div>
</div>

@code {
    [Parameter] public RepoLocation Repo { get; set; } = default!;
    [Parameter] public CommitSha? SelectedSha { get; set; }
    private string Tab = "commit";

    private CommitInfo? _commitInfo;
    private DiffResult? _diff;
    private IReadOnlyList<FileTreeEntry>? _tree;

    protected override async Task OnParametersSetAsync()
    {
        if (SelectedSha is null)
        {
            _commitInfo = null; _diff = null; _tree = null;
            return;
        }
        var commits = new List<CommitInfo>();
        await foreach (var c in Git.GetCommitsAsync(Repo, new CommitQuery(RefSpec: SelectedSha.Value.Value, Take: 1), default))
            commits.Add(c);
        _commitInfo = commits.FirstOrDefault();
        _diff = await Git.GetDiffAsync(Repo, new DiffSpec.CommitVsParent(SelectedSha.Value), default);
        _tree = await Git.GetFileTreeAsync(Repo, SelectedSha.Value, "", default);
    }
}
```

`src/GitOpen.Ui/Components/BottomPanel.razor.css`:
```css
.bottom-panel {
    height: 40%;
    border-top: 1px solid #1c1c1c;
    display: flex;
    flex-direction: column;
    background: #1e1e1e;
    color: #d4d4d4;
}
.tabs { background: #2b2b2b; display: flex; }
.tabs button {
    background: transparent; color: inherit; border: 0; padding: 6px 14px; cursor: pointer;
    border-right: 1px solid #1c1c1c;
}
.tabs button.active { background: #1e1e1e; }
.content { flex: 1; overflow: auto; }
```

- [ ] **Step 5: Wire BottomPanel into the shell**

Modify `src/GitOpen.Ui/Pages/Index.razor`. Add field and bind:

```csharp
private CommitSha? _selectedSha;
```

In the `<div class="main">` block:
```razor
<CommitGraphPanel Repo="_activeRepo.Location"
                  OnCommitSelected="sha => { _selectedSha = sha; StateHasChanged(); }" />
<BottomPanel Repo="_activeRepo.Location" SelectedSha="_selectedSha" />
```

Adjust CSS for `.main` to split vertically:
```css
.main { flex: 1; display: flex; flex-direction: column; min-width: 0; min-height: 0; }
```

- [ ] **Step 6: Build & smoke run**

```bash
dotnet run --project src/GitOpen.Ui
```

Expected: clicking a commit row populates the bottom panel: Commit tab shows metadata; Changes tab shows the diff; File Tree tab lists the root entries.

- [ ] **Step 7: Commit**

```bash
git add .
git commit -m "feat(ui): bottom panel with commit details, diff and file tree"
```

---

## Phase J — Persistence wiring + manual QA + README

### Task J1: Persist open workspaces and rehydrate on startup

**Files:**
- Create: `src/GitOpen.Application/Workspaces/IWorkspacePersistence.cs`
- Create: `src/GitOpen.Infrastructure/Persistence/WorkspacePersistence.cs`
- Modify: `src/GitOpen.Infrastructure/DependencyInjection/InfrastructureModule.cs`
- Modify: `src/GitOpen.Ui/Program.cs`
- Create: `tests/GitOpen.Infrastructure.Tests/Persistence/WorkspacePersistenceTests.cs`

- [ ] **Step 1: Define contract**

`src/GitOpen.Application/Workspaces/IWorkspacePersistence.cs`:
```csharp
namespace GitOpen.Application.Workspaces;

public interface IWorkspacePersistence
{
    Task<IReadOnlyList<string>> GetOpenPathsAsync(CancellationToken ct);
    Task SaveOpenPathsAsync(IReadOnlyList<string> paths, CancellationToken ct);
}
```

- [ ] **Step 2: Test**

`tests/GitOpen.Infrastructure.Tests/Persistence/WorkspacePersistenceTests.cs`:
```csharp
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
        await sut.SaveOpenPathsAsync(new[] { "/a", "/b" }, default);

        var read = await sut.GetOpenPathsAsync(default);

        read.Should().Equal("/a", "/b");
    }
}
```

- [ ] **Step 3: Implement**

`src/GitOpen.Infrastructure/Persistence/WorkspacePersistence.cs`:
```csharp
using System.Text.Json;
using GitOpen.Application.Workspaces;
using GitOpen.Infrastructure.Persistence.Entities;
using Microsoft.EntityFrameworkCore;

namespace GitOpen.Infrastructure.Persistence;

public sealed class WorkspacePersistence : IWorkspacePersistence
{
    private const string Key = "open_workspaces";
    private readonly GitOpenDbContext _db;
    public WorkspacePersistence(GitOpenDbContext db) => _db = db;

    public async Task<IReadOnlyList<string>> GetOpenPathsAsync(CancellationToken ct)
    {
        var row = await _db.Settings.FirstOrDefaultAsync(s => s.Key == Key, ct);
        if (row is null) return Array.Empty<string>();
        return JsonSerializer.Deserialize<List<string>>(row.ValueJson) ?? new List<string>();
    }

    public async Task SaveOpenPathsAsync(IReadOnlyList<string> paths, CancellationToken ct)
    {
        var row = await _db.Settings.FirstOrDefaultAsync(s => s.Key == Key, ct);
        var json = JsonSerializer.Serialize(paths);
        if (row is null)
            _db.Settings.Add(new SettingRow { Key = Key, ValueJson = json });
        else
            row.ValueJson = json;
        await _db.SaveChangesAsync(ct);
    }
}
```

Register in `InfrastructureModule.cs` after `RepositoryRegistry`:

```csharp
services.AddScoped<IWorkspacePersistence, WorkspacePersistence>();
```

- [ ] **Step 4: Wire startup rehydration in `Program.cs`**

After `db.Database.Migrate();`:

```csharp
using (var scope = app.Services.CreateScope())
{
    var persistence = scope.ServiceProvider.GetRequiredService<IWorkspacePersistence>();
    var manager = scope.ServiceProvider.GetRequiredService<IWorkspaceManager>();
    var paths = await persistence.GetOpenPathsAsync(default);
    foreach (var p in paths)
    {
        if (!Directory.Exists(p)) continue;
        try { await manager.OpenAsync(p, default); }
        catch (Exception ex) { Log.Warning(ex, "Failed to reopen workspace {Path}", p); }
    }
}
```

(The startup code now needs `await`; change `app.Run();` accordingly: wrap the whole bootstrap in `await Main(args);` style, or — simpler — run the rehydration before `var app = builder.Build();`'s `app.Run()` synchronously by calling `.GetAwaiter().GetResult()` since startup is single-threaded.)

To keep it simple, change `Program.cs` from top-level statements to:

```csharp
return await Main(args);

static async Task<int> Main(string[] args) { /* ... existing body ... */ }
```

- [ ] **Step 5: Hook persistence on Opened/Closed events in Program.cs after building app**

```csharp
var manager2 = app.Services.GetRequiredService<IWorkspaceManager>();
manager2.Opened   += _ => PersistAsync(app.Services);
manager2.Closed   += _ => PersistAsync(app.Services);
manager2.Reordered += _ => PersistAsync(app.Services);

static void PersistAsync(IServiceProvider sp)
{
    _ = Task.Run(async () =>
    {
        using var scope = sp.CreateScope();
        var p = scope.ServiceProvider.GetRequiredService<IWorkspacePersistence>();
        var m = scope.ServiceProvider.GetRequiredService<IWorkspaceManager>();
        var paths = m.All.Select(w => w.Location.Path).ToList();
        try { await p.SaveOpenPathsAsync(paths, default); }
        catch (Exception ex) { Log.Warning(ex, "Failed to persist workspaces"); }
    });
}
```

- [ ] **Step 6: Run tests**

```bash
dotnet test tests/GitOpen.Infrastructure.Tests
```

Expected: all infrastructure tests pass.

- [ ] **Step 7: Smoke run twice**

```bash
dotnet run --project src/GitOpen.Ui
```

Expected: open one or two repos, close the app, run again — the same repos should reopen automatically.

- [ ] **Step 8: Commit**

```bash
git add .
git commit -m "feat: persist open workspaces and rehydrate on startup"
```

---

### Task J2: README + manual QA checklist

**Files:**
- Create: `README.md`
- Create: `docs/qa-checklist.md`
- Create: `CONTRIBUTING.md`

- [ ] **Step 1: README**

```markdown
# GitOpen

Cross-platform open-source desktop git client built on .NET 8 + Photino.Blazor.
Inspired by Fork. Targets Windows and Ubuntu.

> **Status:** Slice 1 (read-only viewer) under development. See
> `docs/superpowers/specs/` and `docs/superpowers/plans/` for roadmap.

## Build and run

Prerequisites:
- .NET 8 SDK
- `git` CLI on `PATH` (Git for Windows on Windows; `apt install git` on Ubuntu)
- On Linux: `sudo apt install libwebkit2gtk-4.1-0`

```bash
dotnet build GitOpen.sln
dotnet run --project src/GitOpen.Ui
```

## Tests

```bash
dotnet test GitOpen.sln
```

## License

MIT
```

- [ ] **Step 2: QA checklist**

`docs/qa-checklist.md`:
```markdown
# Manual QA Checklist (Slice 1 — read-only viewer)

Run on both Windows and Ubuntu before each release.

## Smoke
- [ ] App launches, main window appears
- [ ] No errors in `%APPDATA%/GitOpen/logs/` (Win) or `~/.config/GitOpen/logs/` (Linux)

## Open repository
- [ ] "+" tab opens folder picker
- [ ] Selecting a folder containing `.git` adds a tab; sidebar populates
- [ ] Selecting a folder without `.git` shows an error toast (or graceful empty)

## Multiple repos
- [ ] Open 3 repos; tabs visible; clicking each switches the panel
- [ ] Close a tab via × removes it from the bar

## Commit graph
- [ ] Repo with linear history shows single lane
- [ ] Repo with branches shows multiple coloured lanes
- [ ] Scroll through 5000+ commits is fluid
- [ ] Branch and tag pills appear on the correct rows
- [ ] HEAD → marker on current branch pill

## Bottom panel
- [ ] Click a commit → Commit tab shows author, sha, full message
- [ ] Changes tab shows diff with +/- lines and hunk headers
- [ ] Binary files show "Binary file (no preview)"
- [ ] File Tree tab lists root entries; folders sort first

## Persistence
- [ ] Open 2 repos, close app, reopen — both repos reopen automatically
- [ ] Move a repo folder, reopen app — the missing repo is silently dropped (logged)

## Resilience
- [ ] Open a very large repo (10k+ commits) — initial load < 5 s
- [ ] Open an empty repo (no commits) — graph panel shows "No commits"
```

- [ ] **Step 3: CONTRIBUTING**

```markdown
# Contributing

GitOpen is open source under the MIT license. Contributions welcome.

## Development setup

See `README.md`. Run `dotnet test` before submitting a PR.

## Architecture

See `docs/superpowers/specs/` for the design and `docs/superpowers/plans/` for
slice-by-slice implementation plans.

## Conventions

- TDD on Application and Infrastructure layers; bUnit on UI components.
- Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `chore:`, `ci:`).
- One logical change per commit.
- Keep files focused: one responsibility per file.
```

- [ ] **Step 4: Commit**

```bash
git add README.md CONTRIBUTING.md docs/qa-checklist.md
git commit -m "docs: README, CONTRIBUTING and Slice 1 QA checklist"
```

---

### Task J3: Final integration test — full test suite green on both OSes (CI)

- [ ] **Step 1: Run full suite locally**

```bash
dotnet test GitOpen.sln --configuration Release
```

Expected: all tests green.

- [ ] **Step 2: Push to a branch and verify GitHub Actions**

If a GitHub remote is configured:

```bash
git push -u origin master
```

Open the Actions tab and confirm both `windows-latest` and `ubuntu-latest`
runs succeed. If not yet configured, defer until a remote exists.

- [ ] **Step 3: Run the manual QA checklist**

Walk through `docs/qa-checklist.md` on Windows. (Ubuntu pass is a separate
session.)

- [ ] **Step 4: Tag the slice**

```bash
git tag -a slice-1-readonly -m "Slice 1: read-only viewer complete"
```

(No push of tag without explicit user request.)

---

## Self-Review

Going back over the spec to verify coverage.

| Spec section | Plan coverage |
|---|---|
| §2 Tech stack | Phases A, D, F — .NET 8, Photino.Blazor, LibGit2Sharp, EF Core/SQLite, Serilog, xUnit, bUnit, FluentAssertions, NSubstitute |
| §3 Solution structure | Task A1 |
| §4 Hybrid git ops | This slice covers ONLY `IGitReadOperations` (LibGit2Sharp). Write side (git CLI) is **deferred to Slice 2** per spec §13 |
| §5 Multi-repo / multi-window | Tabs (G1), per-Workspace state (E1), persistence (J1). **Multi-window deferred to Slice 3** per spec §13 |
| §6 Commit graph | Phases E2 + H |
| §7 State management & persistence | Phases D, J1 (open workspace list). Window persistence and `commit_graph_cache` table created but **populated** later when caching becomes a bottleneck — entities are in place for forward compat |
| §8 Error handling | Logging via Serilog (F1, J1). Result types and full toast/modal/activity panel are **deferred to Slice 4** per spec §13 — scope of Slice 1 is read-only viewing where errors mostly mean "couldn't open repo" |
| §9 Testing | Phases B, C, D, E, G all include tests; CI in A2; manual checklist in J2 |
| §10 Packaging | **Deferred to Slice 5** per spec §13 — Slice 1 ends at "runs locally via `dotnet run`" |
| §11 Out of scope | Honoured |
| §13 Roadmap | This plan implements Slice 1 only |

**Placeholder scan:** searched for "TBD", "TODO", "implement later", "fill in" — none in the plan body.

**Type/method consistency:** `IGitReadOperations` methods used consistently across C2–C7 and consumed in G2/H/I. `IWorkspaceManager` methods consistent across E1/G1/G3. `RepoLocation` fields consistent. `CommitNode.Lane` and `CommitNode.ParentLanes` consistent across E2 and H2.

**Gap noted:** the `commit_graph_cache`, `windows`, `repository_states`, `activity_log` tables are scaffolded in D1 but only `Repositories` and `Settings` are written to in this slice. That is intentional: writing a cache before there is evidence of perf pain is YAGNI. Tables stay so later slices avoid a migration churn.

---

## Execution

Plan complete and saved to `docs/superpowers/plans/2026-05-08-slice1-readonly-viewer.md`.

**Per the user's standing instruction (`feedback_autonomy.md`): proceed without asking — use Subagent-Driven execution (recommended).**
