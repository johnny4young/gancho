# Contributing

Gancho is open source under the [MIT license](LICENSE). Contributions — bug
reports, fixes, and features — are welcome. Open an issue to discuss larger
changes first, then send a pull request.

## Prerequisites

- macOS 26+, Xcode 26+
- XcodeGen: `brew install xcodegen`

## Workflow

```bash
make test      # fast feedback: package unit tests
make open      # generate + open the Xcode project
make format    # before every commit
make lint      # CI runs this with --strict
```

Conventions live in [AGENTS.md](AGENTS.md). Architecture decisions live in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Product scope and acceptance
criteria are tracked in the maintainer's local planning docs (not committed) —
PRs and commits describe the functionality they deliver.

## Branches & pull requests

- **Never commit straight to `main`.** Branch off `main` with a
  [Conventional Commits](https://www.conventionalcommits.org/)-style name:
  `feat/…`, `fix/…`, `refactor/…`, `chore/…`, `docs/…`.
- One coherent change per branch. Keep the PR reviewable; split unrelated work.
- Open the PR against `main` (`gh pr create --base main`). Use Conventional
  Commits for the title and messages.
- **CI must be green before merge.** The `CI` workflow builds the macOS and iOS
  apps, runs the package test suite with coverage (≥ 80% floor), and enforces
  swift-format + SwiftLint and the metadata/site/product-truth gates. Run the
  same checks locally first with `make lint` and `make test`.
- PRs merge by **squash**, and **the branch is deleted automatically on merge**
  — start each new change from a fresh branch off the updated `main` rather than
  reusing a merged one.
- Don't put internal planning identifiers in code comments, commit messages, or
  PR text; the product-truth gate rejects them.
