# Contributing

GitOpen is open source under the MIT license. Contributions are welcome.

## Development setup

See [`README.md`](README.md) for prerequisites and how to build and run. Before
submitting a PR, make sure the suite is green:

```bash
flutter analyze
flutter test
```

## Architecture

See `docs/superpowers/specs/` for the designs and `docs/superpowers/plans/` for the
slice-by-slice implementation plans.

## Conventions

- TDD on the Application and Infrastructure layers; widget tests for UI.
- [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `docs:`, `test:`, `chore:`, `ci:`, `build:`, `perf:`).
- One logical change per commit; keep files focused (one responsibility per file).
- `main` is PR-gated. App-code changes must bump `version` in `pubspec.yaml`; CD
  publishes `v<version>` on merge.
