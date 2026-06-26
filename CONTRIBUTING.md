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
